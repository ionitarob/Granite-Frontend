# ConfigTool Granite

A new Flutter project.

## Serial label workflow API

The serial label generator screen integrates with three REST endpoints exposed by the backend. Each call supports the `include_inactive` flag (default `false`) to toggle whether inactive resources are returned.

| Endpoint | Method | Description |
| --- | --- | --- |
| `/serials/labels/operators` | GET | Lists every operator plus the number of total and active label types available. Accepts `include_inactive=true` to show archived operators. |
| `/serials/labels/types?operador=<name>` | GET | Returns the label/article definitions for the specified operator, including Orange/Vodafone metadata like `codigo_letra` or `sap_cliente`. Honors `include_inactive`. |

> ℹ️ Etiquetas Orange y Vodafone ahora se generan directamente en el frontend siguiendo las reglas de negocio descritas en el ticket: Orange usa `yyyyMMdd + código + correlativo` (p.ej. `20251124EG00001`) y Vodafone usa `sap + año + letra mes + día + correlativo`. El backend únicamente interviene cuando se registran las cajas mediante `/serials/change`.
