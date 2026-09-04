console.log("Lancement backend NeoSurveil...");

require('dotenv').config();

const express    = require('express');
const { Pool }   = require('pg');
const bcrypt     = require('bcrypt');
const jwt        = require('jsonwebtoken');
const nodemailer = require('nodemailer');
const cors       = require('cors');
const mqtt       = require('mqtt');
const fs         = require('fs');
const { InfluxDB, Point } = require('@influxdata/influxdb-client');
const { createServer }    = require('http');
const { Server }          = require('socket.io');

const app        = express();
const httpServer = createServer(app);
const io         = new Server(httpServer, { cors: { origin: '*' } });

app.use(express.json());
app.use(cors());

// ==================== VALIDATION ENV ====================
const JWT_SECRET = process.env.JWT_SECRET;
if (!JWT_SECRET || JWT_SECRET.length < 32) {
  console.error("JWT_SECRET invalide ou trop court (min 32 chars)");
  process.exit(1);
}

// ==================== POSTGRES ====================
const pool = new Pool({
  host:     process.env.PG_HOST     || 'postgres',
  port:     process.env.PG_PORT     || 5432,
  database: process.env.PG_DB       || 'neosurveil',
  user:     process.env.PG_USER     || 'admin',
  password: process.env.PG_PASS     || 'adminpass123',
});

// ==================== ADMIN AUTO ====================
async function ensureAdmin() {
  try {
    const res  = await pool.query("SELECT * FROM users WHERE email='admin@hopital.tn'");
    const hash = await bcrypt.hash('Admin123', 12);
    if (res.rows.length === 0) {
      await pool.query(
        `INSERT INTO users (name, email, password_hash, role, status)
         VALUES ('Admin', 'admin@hopital.tn', $1, 'Admin', 'active')`,
        [hash]
      );
      console.log("Admin créé automatiquement");
    } else if (res.rows[0].status !== 'active' || res.rows[0].role !== 'Admin') {
      await pool.query(
        `UPDATE users SET password_hash=$1, status='active', role='Admin'
         WHERE email='admin@hopital.tn'`,
        [hash]
      );
      console.log("Admin mis à jour");
    } else {
      console.log("Admin déjà présent");
    }
  } catch (err) {
    console.error("Erreur ensureAdmin:", err);
  }
}

// ==================== SMTP ====================
const transporter = nodemailer.createTransport({
  host:   process.env.SMTP_HOST,
  port:   Number(process.env.SMTP_PORT),
  secure: true,
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS,
  },
});

// ==================== INFLUX ====================
const influxDB = new InfluxDB({
  url:   process.env.INFLUX_URL,
  token: process.env.INFLUX_TOKEN,
});

const writeApi = influxDB.getWriteApi(
  process.env.INFLUX_ORG,
  process.env.INFLUX_BUCKET
);

const queryApi = influxDB.getQueryApi(process.env.INFLUX_ORG);

// ==================== MQTT TLS ====================
const mqttOptions = {
  username: process.env.MQTT_USER,
  password: process.env.MQTT_PASS,
};

const caCertPath = process.env.MQTT_CA_CERT || '/app/certs/ca.crt';
if (fs.existsSync(caCertPath)) {
  mqttOptions.ca                 = fs.readFileSync(caCertPath);
  mqttOptions.rejectUnauthorized = false;
  console.log("MQTT TLS activé (port 8883)");
} else {
  console.log("Certificat CA non trouvé — MQTT sans TLS");
}

const mqttClient = mqtt.connect(process.env.MQTT_URL, mqttOptions);

mqttClient.on('connect', () => {
  console.log("MQTT connecté :", process.env.MQTT_URL);
  mqttClient.subscribe('baby/sensors/+');
});

mqttClient.on('error', (err) => {
  console.error("MQTT erreur:", err.message);
});

// ==================== MIDDLEWARES ====================
function authMiddleware(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer '))
    return res.status(401).json({ error: "Token requis" });
  try {
    req.user = jwt.verify(authHeader.split(' ')[1], JWT_SECRET);
    next();
  } catch {
    res.status(401).json({ error: "Token invalide ou expiré" });
  }
}

function adminOnly(req, res, next) {
  if (req.user.role !== 'Admin')
    return res.status(403).json({ error: "Accès réservé à l'administrateur" });
  next();
}

// ==================== EMAIL ALERTE ====================
async function sendAlertEmail(litId, alert) {
  try {
    const users = await pool.query(
      `SELECT email, name, role FROM users
       WHERE status = 'active' AND role IN ('Medecin', 'Infirmier')`
    );
    for (const u of users.rows) {
      await transporter.sendMail({
        from:    process.env.SMTP_USER,
        to:      u.email,
        subject: `Alerte ${alert.type} — ${litId}`,
        html: `
          <h2>Alerte Néonatale</h2>
          <p><b>Lit:</b> ${litId}</p>
          <p><b>Type:</b> ${alert.type}</p>
          <p><b>Valeur:</b> ${alert.valeur} ${alert.unite}</p>
          <p><b>Gravité:</b> ${alert.gravite}</p>
          <hr>
          <p>Destinataire: ${u.name} (${u.role})</p>
        `
      });
    }
    console.log(`Email alerte envoyé → ${litId}:${alert.type}`);
  } catch (err) {
    console.error("Erreur envoi email alerte:", err.message);
  }
}

// ==================== SYSTÈME ANTI-SPAM ====================
// 3 niveaux de protection :
//   1. Debounce  : N lectures consécutives anormales avant d'alerter
//   2. Cooldown Socket.io : max 1 alerte / 30s par lit+type
//   3. Cooldown email     : max 1 email  / 10min par lit+type

const alertCounters   = {};   // { "lit6:HR": 3, ... }
const lastSocketAlert = {};   // { "lit6:HR": timestamp, ... }
const lastEmailAlert  = {};   // { "lit6:HR": timestamp, ... }

const DEBOUNCE_READINGS  = 3;
const SOCKET_COOLDOWN_MS = 30_000;
const EMAIL_COOLDOWN_MS  = 600_000;

function canSendSocketAlert(litId, type) {
  const key = `${litId}:${type}`;
  const now = Date.now();
  if (now - (lastSocketAlert[key] || 0) < SOCKET_COOLDOWN_MS) return false;
  lastSocketAlert[key] = now;
  return true;
}

function canSendEmail(litId, type) {
  const key = `${litId}:${type}`;
  const now = Date.now();
  if (now - (lastEmailAlert[key] || 0) < EMAIL_COOLDOWN_MS) return false;
  lastEmailAlert[key] = now;
  return true;
}

function alertMessage(type, valeur, unite) {
  switch (type) {
    case 'HR':     return `Fréquence cardiaque critique : ${valeur} bpm`;
    case 'SPO2':   return `SpO2 critique : ${valeur} %`;
    case 'TEMP':   return `Température corporelle élevée : ${valeur} °C`;
    case 'PLEURS': return 'Pleurs détectés';
    default:       return `Alerte ${type} : ${valeur} ${unite}`;
  }
}

// ==================== MQTT HANDLER ====================
mqttClient.on('message', async (topic, message) => {
  try {
    const data  = JSON.parse(message.toString());
    const litId = topic.split('/')[2];

    // Strict boolean (ESP32 envoie true/false)
    const crying = data.crying === true;

    // 1. Sauvegarde InfluxDB
    // Champ "humidite" — synchronisé avec ESP32 (doc["humidite"])
    const point = new Point('vitals')
      .tag('litId',    litId)
      .floatField('bpm',       data.bpm       || 0)
      .floatField('spo2',      data.spo2      || 0)
      .floatField('temp_body', data.temp_body || 0)
      .floatField('temp_env',  data.temp_env  || 0)
      .floatField('humidite',  data.humidite  || 0)
      .intField('crying',      crying ? 1 : 0);
    writeApi.writePoint(point);
    await writeApi.flush();

    // 2. Diffusion temps réel vers Flutter (toujours, sans throttle)
    io.to(litId).emit('vitals', { ...data, crying });

    // 3. Alertes avec debounce + cooldown
    const checks = [
      {
        type:     'HR',
        abnormal: (data.bpm || 0) > 160,
        valeur:   data.bpm,
        unite:    'bpm',
        gravite:  'CRITIQUE',
        debounce: DEBOUNCE_READINGS,
      },
      {
        type:     'SPO2',
        abnormal: data.spo2 > 0 && data.spo2 < 92,
        valeur:   data.spo2,
        unite:    '%',
        gravite:  'CRITIQUE',
        debounce: DEBOUNCE_READINGS,
      },
      {
        type:     'TEMP',
        abnormal: data.temp_body > 0 && data.temp_body > 37.5,
        valeur:   data.temp_body,
        unite:    '°C',
        gravite:  'WARNING',
        debounce: DEBOUNCE_READINGS,
      },
      {
        // Pleurs : debounce = 1 (déjà filtré par amplitude côté ESP32)
        type:     'PLEURS',
        abnormal: crying,
        valeur:   'Détectés',
        unite:    '',
        gravite:  'WARNING',
        debounce: 1,
      },
    ];

    for (const check of checks) {
      const key = `${litId}:${check.type}`;

      // Mise à jour compteur debounce
      if (check.abnormal) {
        alertCounters[key] = (alertCounters[key] || 0) + 1;
      } else {
        alertCounters[key] = 0;  // retour normal → reset
        continue;
      }

      // Pas encore assez de lectures consécutives
      if (alertCounters[key] < check.debounce) continue;

      // Cooldown Socket.io
      if (!canSendSocketAlert(litId, check.type)) continue;

      const payload = {
        type:    check.type,
        valeur:  check.valeur,
        unite:   check.unite,
        gravite: check.gravite,
        message: alertMessage(check.type, check.valeur, check.unite),
      };

      io.to(litId).emit('alert', payload);
      console.log(`Alerte socket → ${litId}:${check.type} (${alertCounters[key]} lectures)`);

      // Email uniquement pour CRITIQUE et avec cooldown 10min
      if (check.gravite === 'CRITIQUE' && canSendEmail(litId, check.type)) {
        await sendAlertEmail(litId, payload);
      }
    }

  } catch (err) {
    console.error("Erreur handler MQTT:", err.message);
  }
});

// ==================== ROUTE : HISTORIQUE INFLUX ====================
// GET /api/history/:litId?range=1h
// range accepté : 1h | 6h | 24h | 7d
// Retourne les valeurs agrégées par minute pour le graphique Flutter
app.get('/api/history/:litId', authMiddleware, async (req, res) => {
  const { litId } = req.params;
  const allowedRanges = ['1h', '6h', '24h', '7d'];
  const range = allowedRanges.includes(req.query.range) ? req.query.range : '1h';

  // Intervalle d'agrégation adapté à la plage
  const aggregateWindow = range === '7d' ? '10m'
                        : range === '24h' ? '5m'
                        : '1m';

  const flux = `
    from(bucket: "${process.env.INFLUX_BUCKET}")
      |> range(start: -${range})
      |> filter(fn: (r) => r._measurement == "vitals" and r.litId == "${litId}")
      |> filter(fn: (r) =>
            r._field == "bpm"       or
            r._field == "spo2"      or
            r._field == "temp_body" or
            r._field == "temp_env"  or
            r._field == "humidite"  or
            r._field == "crying")
      |> aggregateWindow(every: ${aggregateWindow}, fn: mean, createEmpty: false)
      |> yield(name: "mean")
  `;

  try {
    const rows = [];
    await new Promise((resolve, reject) => {
      queryApi.queryRows(flux, {
        next(row, tableMeta) {
          const obj = tableMeta.toObject(row);
          rows.push({ time: obj._time, field: obj._field, value: obj._value });
        },
        error: reject,
        complete: resolve,
      });
    });

    const result = { bpm: [], spo2: [], temp_body: [], temp_env: [], humidite: [], crying: [] };
    for (const row of rows) {
      if (result[row.field] !== undefined) {
        result[row.field].push({ t: row.time, v: parseFloat(row.value.toFixed(2)) });
      }
    }
    res.json(result);

  } catch (err) {
    console.error("Erreur InfluxDB query:", err.message);
    res.status(500).json({ error: "Erreur lecture historique" });
  }
});

// ==================== ROUTE : INSCRIPTION ====================
app.post('/api/register', async (req, res) => {
  const { name, email, password, role, cin } = req.body;
  if (!name || !email || !password)
    return res.status(400).json({ error: "Nom, email et mot de passe requis" });
  if (password.length < 6)
    return res.status(400).json({ error: "Mot de passe minimum 6 caractères" });
  try {
    const existing = await pool.query('SELECT id FROM users WHERE email = $1', [email.toLowerCase()]);
    if (existing.rows.length > 0)
      return res.status(409).json({ error: "Cet email est déjà utilisé" });
    const passwordHash = await bcrypt.hash(password, 12);
    await pool.query(
      `INSERT INTO users (name, email, password_hash, role, cin, status)
       VALUES ($1, $2, $3, $4, $5, 'pending')`,
      [name, email.toLowerCase(), passwordHash, role || 'Infirmier', cin]
    );
    try {
      const admins = await pool.query(
        `SELECT email FROM users WHERE role = 'Admin' AND status = 'active'`
      );
      for (const admin of admins.rows) {
        await transporter.sendMail({
          from:    process.env.SMTP_USER,
          to:      admin.email,
          subject: "Nouvelle demande de compte — NeoSurveil",
          html: `
            <h2>Nouvelle demande de compte</h2>
            <p><b>Nom:</b> ${name}</p>
            <p><b>Email:</b> ${email}</p>
            <p><b>Rôle:</b> ${role || 'Infirmier'}</p>
            <p><b>CIN:</b> ${cin || 'Non renseigné'}</p>
          `
        });
      }
    } catch (mailErr) {
      console.error("Email admin non envoyé:", mailErr.message);
    }
    res.status(201).json({ message: "Demande envoyée. En attente d'approbation." });
  } catch (err) {
    console.error("Erreur inscription:", err);
    res.status(500).json({ error: "Erreur serveur lors de l'inscription" });
  }
});

// ==================== ROUTE : CONNEXION ====================
app.post('/api/login', async (req, res) => {
  const { email, password } = req.body;
  try {
    const result = await pool.query('SELECT * FROM users WHERE email = $1', [email.toLowerCase()]);
    if (result.rows.length === 0)
      return res.status(401).json({ error: "Email ou mot de passe incorrect" });
    const user = result.rows[0];
    if (user.status === 'pending')
      return res.status(403).json({ error: "Votre compte est en attente d'approbation." });
    if (user.status === 'rejected')
      return res.status(403).json({ error: "Votre demande a été refusée. Contactez l'administration." });
    if (user.status !== 'active')
      return res.status(403).json({ error: "Compte désactivé." });
    const valid = await bcrypt.compare(password, user.password_hash);
    if (!valid)
      return res.status(401).json({ error: "Email ou mot de passe incorrect" });
    const token = jwt.sign(
      { userId: user.id, email: user.email, role: user.role },
      JWT_SECRET,
      { expiresIn: '24h' }
    );
    res.json({ token, user: { id: user.id, name: user.name, email: user.email, role: user.role } });
  } catch (err) {
    console.error("Erreur connexion:", err);
    res.status(500).json({ error: "Erreur serveur" });
  }
});

// ==================== ROUTES ADMIN ====================
app.get('/api/admin/pending', authMiddleware, adminOnly, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT id, name, email, role, cin, created_at
       FROM users WHERE status = 'pending' ORDER BY created_at DESC`
    );
    res.json(result.rows);
  } catch (err) {
    console.error("Erreur pending:", err);
    res.status(500).json({ error: "Erreur serveur" });
  }
});

app.get('/api/admin/users', authMiddleware, adminOnly, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT id, name, email, role, cin, status, created_at
       FROM users ORDER BY created_at DESC`
    );
    res.json(result.rows);
  } catch (err) {
    console.error("Erreur users:", err);
    res.status(500).json({ error: "Erreur serveur" });
  }
});

app.post('/api/admin/approve/:id', authMiddleware, adminOnly, async (req, res) => {
  try {
    const result = await pool.query(
      `UPDATE users SET status = 'active'
       WHERE id = $1 AND status = 'pending' RETURNING name, email`,
      [req.params.id]
    );
    if (result.rows.length === 0)
      return res.status(404).json({ error: "Demande non trouvée ou déjà traitée" });
    const user = result.rows[0];
    try {
      await transporter.sendMail({
        from:    process.env.SMTP_USER,
        to:      user.email,
        subject: "Compte approuvé — NeoSurveil",
        html:    `<h2>Bienvenue ${user.name} !</h2><p>Votre compte a été approuvé. Vous pouvez maintenant vous connecter.</p>`
      });
    } catch (mailErr) {
      console.error("Email approbation non envoyé:", mailErr.message);
    }
    res.json({ message: `Compte de ${user.name} approuvé.` });
  } catch (err) {
    console.error("Erreur approbation:", err);
    res.status(500).json({ error: "Erreur serveur" });
  }
});

app.post('/api/admin/reject/:id', authMiddleware, adminOnly, async (req, res) => {
  try {
    const result = await pool.query(
      `UPDATE users SET status = 'rejected'
       WHERE id = $1 AND status = 'pending' RETURNING name, email`,
      [req.params.id]
    );
    if (result.rows.length === 0)
      return res.status(404).json({ error: "Demande non trouvée ou déjà traitée" });
    const user = result.rows[0];
    try {
      await transporter.sendMail({
        from:    process.env.SMTP_USER,
        to:      user.email,
        subject: "Demande refusée — NeoSurveil",
        html:    `<h2>Bonjour ${user.name},</h2><p>Votre demande a été refusée. Contactez l'administration.</p>`
      });
    } catch (mailErr) {
      console.error("Email rejet non envoyé:", mailErr.message);
    }
    res.json({ message: `Compte de ${user.name} rejeté.` });
  } catch (err) {
    console.error("Erreur rejet:", err);
    res.status(500).json({ error: "Erreur serveur" });
  }
});

// ==================== SOCKET ====================
io.on('connection', (socket) => {
  socket.on('join_lit', (litId) => {
    socket.join(litId);
    console.log(`Socket ${socket.id} rejoint ${litId}`);
  });
});

// ==================== DÉMARRAGE ====================
const PORT = process.env.PORT || 3000;
httpServer.listen(PORT, async () => {
  console.log(`Serveur démarré sur http://0.0.0.0:${PORT}`);
  await ensureAdmin();
});