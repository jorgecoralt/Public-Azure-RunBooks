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

