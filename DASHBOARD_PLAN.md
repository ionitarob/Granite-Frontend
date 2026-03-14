
Refactoring `OrderDetailScreen` to support "Dashboard Mode".

### Components of the new Dashboard:

1.  **Top Row (Pinkish cards):**
    *   `_buildMiniInformationCard`: Compact version of `_buildHeaderCard`.
    *   `_buildMiniLinesCard`: Compact version of `_buildLinesCard`.
    *   `_buildMiniServicesCard`: Compact version of `_buildServicesCard`.
    *   `_buildMiniObservationsCard`: Compact version of `_buildObservationsCard`.

2.  **Main Area (Embedded Service Screen):**
    *   Need to modify `RegistroServidorScreen`, `SerialLinkScreen`, `SerialChangeScreen`, `XiaomiRegistroOrdenScreen`, and `CerrarCesbScreen` to support an `isEmbedded` property.
    *   When `isEmbedded` is true, these screens should NOT return a `Scaffold` or `AppBar`, and should probably omit their `MainSidebar` / `EdgeNavHandle`.

3.  **Bottom Area:**
    *   `_buildQualityLogsRow`: Contains `_buildQualityQualityCard` and System Log.

### Proposed changes to `OrderDetailScreen`:

*   Add `bool _isDashboardMode = false;` (or similar toggle).
*   In `_buildDashboard`, if `_isDashboardMode` is true, use a `Column` with:
    *   `Row` (or `GridView`) for the top 4 cards.
    *   `Expanded` (or fixed height) for the embedded service widget.
    *   `Row` for the bottom logs.

### Mapping for Embedded Widgets:

| Family | Embedded Widget |
| :--- | :--- |
| ORDENADORES SERVIDOR | `RegistroServidorScreen(initialOrderNbr: orderNbr, isEmbedded: true)` |
| MANIPULACIÓN Y ETIQUETADO | `SerialLinkScreen(initialOrder: orderNbr, isEmbedded: true)` |
| CAMBIO DE SERIAL | `SerialChangeScreen(initialOrder: orderNbr, isEmbedded: true)` |
| XIAOMI ETIQUETADO | Pick between `XiaomiRegistroOrdenScreen` or `CerrarCesbScreen` (maybe show both or pick one based on state). |

### Action Plan:

1.  **Modify Target Screens:**
    *   Add `isEmbedded` parameter to constructors.
    *   Update `build` methods to return `Container`/`Column` instead of `Scaffold` when `isEmbedded` is true.
    *   Remove `AppBar` and `MainSidebar` dependencies when embedded.

2.  **Refactor `OrderDetailScreen`:**
    *   Create `_buildMini*` variants of the existing cards.
    *   Implement the new dashboard layout.
    *   Add a toggle in the UI to switch to Dashboard Mode.
