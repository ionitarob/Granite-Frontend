# Contrato Backend: Masterizacion por Orden

Fecha: 2026-03-13

## Objetivo
Garantizar trazabilidad completa OrderOps <-> Sentinel para que:
- Cada equipo maquetado quede asociado a una orden.
- Se generen logs persistentes por equipo.
- Se publique un archivo CSV por equipo (nombre `SERIAL.csv`) en ARCHIVOS de la orden.
- Se puedan descargar logs individuales y en lote (zip) sin depender del frontend como fuente de verdad.

## Principios
- Backend es la unica fuente de verdad de estado y auditoria.
- Idempotencia estricta para no duplicar logs/archivos ante reintentos.
- Eventos en tiempo real (WS) no sustituyen persistencia en DB.
- Frontend solo visualiza y consume APIs.

## Modelo de Datos Minimo

### 1) imaging_runs
Representa una ejecucion de maquetado por equipo.

Campos sugeridos:
- id (PK)
- order_id (FK -> orderops_agentorder.id)
- serial (varchar, index)
- mac (varchar, nullable, index)
- run_id (varchar, unique)
- switch_id (int, nullable)
- port_id (int, nullable)
- selected_image (varchar)
- status (enum: queued, running, done, failed, canceled)
- started_at (datetime)
- finished_at (datetime, nullable)
- created_at / updated_at

Restricciones:
- UNIQUE(run_id)
- INDEX(order_id, status)
- INDEX(order_id, serial)

### 2) imaging_run_events
Eventos cronologicos por run.

Campos sugeridos:
- id (PK)
- run_id (FK -> imaging_runs.run_id)
- order_id (FK -> orderops_agentorder.id)
- serial (varchar)
- event_type (varchar)  // progress, stage_change, done, failed, etc
- stage (varchar, nullable)
- progress (int, nullable)
- message (text, nullable)
- payload_json (json, nullable)
- event_ts (datetime)
- created_at

Restricciones:
- INDEX(order_id, event_ts)
- INDEX(run_id, event_ts)

### 3) imaging_artifacts
Artefactos exportados por backend (ej: CSV por equipo).

Campos sugeridos:
- id (PK)
- order_id (FK)
- run_id (varchar, nullable)
- serial (varchar)
- artifact_type (enum: per_device_csv, order_zip)
- file_name (varchar)  // SERIAL.csv
- file_path (varchar)
- checksum_sha256 (varchar)
- created_at

Restricciones:
- UNIQUE(order_id, serial, artifact_type) para per_device_csv

## Reglas de Negocio

### Asociacion Order <-> Run
Al recibir inicio de maquetado o primer evento con contexto valido:
1. Resolver `order_id` por prioridad:
   - order_id explicito en evento/API
   - order_id de `switch_port` activo
   - rechazar y loggear si no hay contexto
2. Crear/actualizar `imaging_runs` por `run_id` (upsert).

### Idempotencia
- Si llega el mismo evento (misma firma run_id + event_type + event_ts + progress), no duplicar.
- Si ya existe artefacto `SERIAL.csv` para esa orden y serial:
  - Reemplazar contenido si checksum distinto, o
  - Mantener y no duplicar registro.

### Cierre de Run
Cuando status pase a `done` o `failed`:
1. Persistir estado final en `imaging_runs`.
2. Generar CSV por equipo con nombre `SERIAL.csv`.
3. Registrar archivo en `imaging_artifacts`.
4. Publicar archivo en ARCHIVOS de la orden (tabla/fuente usada por `/agent-orders/{id}/photos`).

## Formato CSV por Equipo (SERIAL.csv)
Columnas minimas:
- order_id
- order_nbr
- serial
- run_id
- mac
- switch
- port
- image
- status
- started_at
- finished_at
- duration_seconds
- final_stage
- final_progress
- error_message

Opcional:
- throughput_avg_mbps
- bytes_total
- bytes_done
- operador

## Endpoints Requeridos

### 1) Resumen de maquetado por orden
GET `/orderops/agent-orders/{order_id}/imaging/summary`

Response ejemplo:
```
{
  "order_id": 43774,
  "configured_ports": 220,
  "matched_devices": 208,
  "running": 12,
  "completed": 196,
  "failed": 4,
  "last_event_at": "2026-03-13T11:42:10Z"
}
```

### 2) Runs por orden
GET `/orderops/agent-orders/{order_id}/imaging/runs?status=done&limit=500`

### 3) Eventos por orden
GET `/orderops/agent-orders/{order_id}/imaging/events?serial=ABC123&run_id=...`

### 4) Descargar CSV por serial
GET `/orderops/agent-orders/{order_id}/imaging/artifacts/{serial}.csv`

### 5) Descargar lote zip
GET `/orderops/agent-orders/{order_id}/imaging/artifacts.zip`
- Incluye todos los `SERIAL.csv` de la orden.

### 6) (Interno) Ingesta de evento Sentinel
POST `/sentinel/api/imaging-event`
Body minimo:
```
{
  "order_id": 43774,
  "run_id": "run-uuid",
  "serial": "ABC123",
  "mac": "aa:bb:cc:dd:ee:ff",
  "event_type": "progress",
  "stage": "wim_apply",
  "progress": 57,
  "message": "Applying image",
  "event_ts": "2026-03-13T11:40:01Z",
  "payload": {...}
}
```

## Integracion con ARCHIVOS de Orden
El backend, al generar `SERIAL.csv`, debe insertar el archivo en la misma fuente que alimenta:
- GET `/orderops/agent-orders/{id}/photos`

Esto permite que OrderDetail muestre/descargue los CSV sin cambios estructurales en frontend.

## Estrategia de Implementacion (Django)
1. Crear migraciones para `imaging_runs`, `imaging_run_events`, `imaging_artifacts`.
2. Implementar servicio de upsert de run y append de eventos.
3. Implementar generador CSV por serial y writer en storage.
4. Conectar generacion de CSV al cambio de estado final.
5. Exponer endpoints read-only para resumen/runs/events/artifacts.
6. Añadir endpoint zip por orden.
7. Añadir tests de idempotencia y concurrencia.

## Tests Minimos
- Dado run_id repetido, no se duplica `imaging_runs`.
- Dado evento repetido, no se duplica `imaging_run_events`.
- Al finalizar 200 equipos, existen 200 `SERIAL.csv` en ARCHIVOS.
- Descarga zip contiene exactamente los CSV esperados.
- `summary.completed` coincide con runs status=done.

## Observabilidad
- Log estructurado con `order_id`, `run_id`, `serial`.
- Metricas:
  - imaging_runs_created_total
  - imaging_runs_completed_total
  - imaging_runs_failed_total
  - imaging_csv_generated_total
  - imaging_csv_generation_errors_total

## Seguridad
- Endpoints protegidos por auth actual.
- Descargas autorizadas por permisos de OrderOps.
- Sanitizar `serial` para nombre de archivo seguro.

## Responsabilidad Frontend
- Enviar `order_id` en contexto de seleccion/ejecucion.
- Mostrar contadores consumiendo `summary` backend.
- Mostrar ARCHIVOS y permitir descarga.
- No generar CSV finales como fuente oficial.

## Criterio de Aceptacion
Se considera completado cuando:
- Una orden con 200 equipos maquetados muestra 200 archivos `SERIAL.csv` en ARCHIVOS.
- Cualquier CSV se puede descargar individualmente.
- Existe descarga zip de todos los logs de la orden.
- Los contadores de resumen salen del backend y cuadran con DB.
