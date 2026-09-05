# 👶 Smart Crib Project — Lit intelligent pour nouveau-nés

Système IoT complet pour la surveillance intelligente d'un lit de bébé, incluant capteurs, application mobile et tableau de bord.

## 🧩 Stack technique
- **Mobile** : Flutter
- **Backend** : Next.js / Node.js
- **Firmware** : Arduino IDE
- **Base relationnelle** : PostgreSQL
- **Base de séries temporelles** : InfluxDB
- **Broker MQTT** : Mosquitto
- **Conteneurisation** : Docker / Docker Compose

## 📁 Structure du projet
smart-crib-project/
├── mobile-app/ # Application Flutter
├── backend/ # API Next.js / Node.js
├── firmware/ # Code Arduino (.ino)
├── mosquitto/ # Config broker MQTT
├── postgres/ # Données PostgreSQL (générées)
├── influxdb/ # Données InfluxDB (générées)
├── docker-compose.yml
├── init.sql
└── .env.example

## 🚀 Installation

### 1. Cloner le dépôt
\`\`\`bash
git clone https://github.com/ton-username/smart-crib-project.git
cd smart-crib-project
\`\`\`

### 2. Configurer les variables d'environnement
\`\`\`bash
cp .env.example .env
\`\`\`
Puis remplis `.env` avec tes propres valeurs.

### 3. Lancer les conteneurs
\`\`\`bash
docker-compose up -d
\`\`\`

### 4. Vérifier que tout tourne
\`\`\`bash
docker-compose ps
\`\`\`

## 📱 Application mobile (Flutter)
\`\`\`bash
cd mobile-app
flutter pub get
flutter run
\`\`\`

## 🔧 Firmware (Arduino)
Ouvrir le dossier `firmware/` dans Arduino IDE, sélectionner la carte et le port, puis téléverser.

## 🛑 Arrêter les conteneurs
\`\`\`bash
docker-compose down
\`\`\`