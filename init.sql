-- ==================== TABLES ====================
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(50) DEFAULT 'Infirmier',
    cin VARCHAR(20),
    status VARCHAR(20) DEFAULT 'pending',
    verification_token VARCHAR(255),
    verified_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS alertes_email (
    id SERIAL PRIMARY KEY,
    baby_id VARCHAR(50),
    couveuse_id VARCHAR(50),
    type_alerte VARCHAR(50),
    gravite VARCHAR(20),
    valeur DECIMAL(6,2),
    destinataire VARCHAR(100),
    envoye_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS user_preferences (
    user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    alertes_email BOOLEAN DEFAULT true,
    niveau_alerte VARCHAR(20) DEFAULT 'ALL'
);

-- ==================== UTILISATEURS PAR DÉFAUT ====================
-- Compte Admin (status = 'active' directement, pas besoin d'approbation)
INSERT INTO users (name, email, password_hash, role, status, cin)
VALUES (
  'Admin Principal',
  'admin@hopital.tn',
  'TEMP',
  'Admin',
  'active',
  '00000000'
)
ON CONFLICT (email) DO NOTHING;

-- Compte Médecin de test (status = 'active' car déjà existant avant la mise à jour)
INSERT INTO users (name, email, password_hash, role, status, cin)
VALUES (
  'Dr. Test',
  'test@hopital.tn',
  '$2b$14$N9qo8uLOickgx2ZMRZoMy.MqrqhmM6JGKpS4G3R1G2tUqYjVQqQq0',
  'Medecin',
  'active',
  '12345678'
) ON CONFLICT (email) DO NOTHING;