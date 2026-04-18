# ConfigTool Granite Frontend

<p align="center">
  <img src="lib/assets/logo.png" alt="Granite Logo" width="120"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" alt="Flutter"/>
  <img src="https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white" alt="Dart"/>
  <img src="https://img.shields.io/badge/version-2.4.0-blue" alt="Version"/>
  <img src="https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20Desktop%20%7C%20Web-lightgrey" alt="Platform"/>
</p>

> A cross-platform operations management tool built with Flutter for warehouse and logistics workflows.

---

## 📸 Screenshots

<p align="center">
  <img src="flutter_01.png" width="280"/>
  <img src="flutter_02.png" width="280"/>
  <img src="flutter_03.png" width="280"/>
</p>

---

## ✨ Features

| Module | Description |
|---|---|
| 🛒 **Amazon Operations** | Grading, sorting, picking, receiving, ICQA, inventory control, batch registration, and more |
| 🏷️ **Serial Management** | Serial linking, serial change, label generation, mask configuration, and change history |
| 🖥️ **Server Registration** | Pre-registration and full server registration workflows |
| 👥 **HR (RRHH)** | Employee onboarding, clock-in/out (fichaje), and user management |
| 📦 **Xiaomi** | Order registration, CESB closing, statistics, and history |
| 📊 **Dashboard** | Order detail dashboards with embedded service screens and quality logs |
| 🔍 **Analysis & Services** | AYS management dashboard and analytics |
| 🖼️ **Sentinel for Imaging** | Active image monitoring and management |
| 📡 **Igualdad** | Stock entry, smartphone/wearable registration, and expedition history |
| 📺 **TV** | TV-specific operational screens |

---

## 🏗️ Tech Stack

- **Framework:** Flutter (≥ 3.x / Dart ≥ 3.9)
- **State management:** Provider
- **Networking:** `http`, `web_socket_channel`
- **Storage:** `shared_preferences`, `flutter_secure_storage`
- **Charts:** `fl_chart`
- **PDF:** `pdf`, `printing`, `syncfusion_flutter_pdfviewer`
- **Barcode / QR:** `mobile_scanner`, `barcode_widget`
- **Audio / TTS / STT:** `audioplayers`, `flutter_tts`, `speech_to_text`
- **File handling:** `file_picker`, `file_selector`, `desktop_drop`, `open_filex`
- **Animations:** `lottie`

---

## 🚀 Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) ≥ 3.x
- Dart ≥ 3.9
- A running instance of the Granite backend (default: `http://10.20.31.10:7000`)

### Installation

```bash
# Clone the repository
git clone https://github.com/ionitarob/Granite-Frontend.git
cd Granite-Frontend

# Install dependencies
flutter pub get

# Run on your target platform
flutter run
```

### Configuration

The backend URL is configured in [`lib/config.dart`](lib/config.dart):

```dart
const String kBackendBaseUrl = 'http://<your-backend-host>:<port>';
```

---

## 📡 Serial Label API

The serial label generator integrates with REST endpoints exposed by the backend. Each call supports the `include_inactive` flag (default `false`) to toggle whether inactive resources are returned.

| Endpoint | Method | Description |
|---|---|---|
| `/serials/labels/operators` | GET | Lists every operator plus the number of total and active label types. Accepts `include_inactive=true` to include archived operators. |
| `/serials/labels/types?operador=<name>` | GET | Returns label/article definitions for the specified operator, including Orange/Vodafone metadata (`codigo_letra`, `sap_cliente`). Honors `include_inactive`. |

> **Note:** Orange and Vodafone labels are generated directly in the frontend:
> - **Orange** → `yyyyMMdd + código + correlativo` (e.g. `20251124EG00001`)
> - **Vodafone** → `sap + year + month letter + day + correlativo`
>
> The backend is only involved when registering boxes via `/serials/change`.

---

## 📁 Project Structure

```
lib/
├── assets/          # Images, animations (Lottie), and other static assets
├── models/          # Data models
├── screens/         # Feature screens grouped by module
│   ├── amazon/
│   ├── analisis_y_serveis/
│   ├── igualdad/
│   ├── orderops/
│   ├── rrhh/
│   ├── sentinel_for_imaging/
│   ├── serials/
│   ├── servers/
│   ├── tv/
│   └── xiaomi/
├── services/        # API clients, providers, and background services
├── themes/          # App themes and styling
├── utils/           # Utility helpers
└── widgets/         # Reusable UI components
```
