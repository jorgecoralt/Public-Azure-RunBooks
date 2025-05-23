# ☁️ Azure Runbooks – Automatización estratégica para bases de datos

Este repositorio recopila *runbooks* diseñados para automatizar tareas críticas en entornos con múltiples bases de datos distribuidas, especialmente cuando estas deben compartir una estructura coherente. Cada script resuelve un problema operativo concreto, mejora la gobernanza y reduce errores humanos, integrando buenas prácticas para entornos Azure SQL Server u on-premise.

---

## ⚙️ Funcionalidades incluidas

### `Sync_Databases_columns.ps1`

Sincroniza estructuras entre bases de datos que deben mantenerse alineadas.  
Compara cada tabla con una base de referencia, detecta campos faltantes, y los agrega automáticamente con sus propiedades correctas (tipo, nullabilidad, valor por defecto).  
Deja trazabilidad en una tabla de logs para auditoría y control.

👉 [**Ver explicación completa y caso de uso**](https://jorgecoral.com/sincronizacion-estructural-de-campos-automatica-en-bases-distribuidas/)



### `Sync_databases_tables.ps1`

Sincroniza tablas nuevas entre bases de datos que deben mantenerse alineadas.  
Compara cada tabla con una base de referencia, detecta cuando una tabla falte en el destino, y la crea automáticamente con sus campos y propiedades correctas (tipo, nullabilidad, valor por defecto).  

👉 [**Ver explicación completa y caso de uso**](https://jorgecoral.com/sincronizacion-estructural-de-tablas-automatica-en-bases-distribuidas/)



### `Optimize_indexes_sql_server.ps1`

Evalúa automáticamente la fragmentación de índices en múltiples bases SQL Server.

Aplica `REBUILD` o `REORGANIZE` según el porcentaje de fragmentación:
- Reorganiza si la fragmentación es mayor al umbral mínimo (`$UmbralReorganize`, por defecto 5%).
- Reconstruye si supera el umbral crítico (`$UmbralRebuild`, por defecto 30%).

Puedes excluir una tabla específica mediante la variable `$excludedTable`.

Este script es ideal para mantener la salud de índices en ejecuciones nocturnas o programadas desde cuentas de Azure Automation (PowerShell 5.1), evitando degradación de rendimiento con un control sencillo y ajustable.

👉 [**Ver explicación completa y caso de uso**](https://jorgecoral.com/mantenimiento-automatico-de-indices-en-multiples-bases-de-datos-sql-server/)
