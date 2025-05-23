# --------------------------------------------
# Creador de tablas que faltan en bases destino - JORGE CORAL TORRES 2025-05-23
# --------------------------------------------

# Importar el módulo SqlServer
Import-Module SqlServer

# Parámetros generales
$ServerName = "MI_URL_DE_AZURE"
$Credential = Get-AutomationPSCredential -Name "MI_CREDENCIAL_AUTOMATION"

# Base de datos de referencia
$OrigenDatabase = "MI_BASE_ORIGINAL"

# Bases destino donde deben existir las mismas tablas
$DatabasesDestino = @(
    "BASE1","BASE2",...,"BASEN"
)

# Extraer todas las tablas del origen
$queryTablas = @"
SELECT TABLE_NAME
FROM [$OrigenDatabase].INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE = 'BASE TABLE'
"@

$tablasOrigen = Invoke-Sqlcmd -ServerInstance $ServerName -Username $Credential.Username `
                               -Password $Credential.GetNetworkCredential().Password `
                               -Database $OrigenDatabase -Query $queryTablas

# Para cada tabla de la base de datos origen
foreach ($tabla in $tablasOrigen) {
    $tableName = $tabla.TABLE_NAME
    Write-Output "Procesando tabla: $tableName"

    # Obtener definición de columnas
    $queryColumnas = @"
SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH,
       NUMERIC_PRECISION, NUMERIC_SCALE, IS_NULLABLE, COLUMN_DEFAULT
FROM [$OrigenDatabase].INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = '$tableName'
ORDER BY ORDINAL_POSITION
"@

    $columnas = Invoke-Sqlcmd -ServerInstance $ServerName -Username $Credential.Username `
                               -Password $Credential.GetNetworkCredential().Password `
                               -Database $OrigenDatabase -Query $queryColumnas

    if (-not $columnas) {
        Write-Output "No se encontraron columnas para $tableName. Saltando..."
        continue
    }

    # Construir sentencia CREATE TABLE
    $columnDefs = @()

    foreach ($col in $columnas) {
        $colDef = "[$($col.COLUMN_NAME)] $($col.DATA_TYPE)"

        # Tipos con longitud
        if ($col.DATA_TYPE -in @("varchar", "nvarchar", "char", "nchar", "binary", "varbinary")) {
            $longitud = $col.CHARACTER_MAXIMUM_LENGTH
            $colDef += if ($longitud -eq -1) { "(MAX)" } else { "($longitud)" }
        }

        # Tipos con precisión
        if ($col.DATA_TYPE -in @("decimal", "numeric")) {
            $colDef += "($($col.NUMERIC_PRECISION),$($col.NUMERIC_SCALE))"
        }

        # NULL o NOT NULL
        $colDef += if ($col.IS_NULLABLE -eq "YES") { " NULL" } else { " NOT NULL" }

        # Default
        if ($col.COLUMN_DEFAULT -and $col.COLUMN_DEFAULT -ne [DBNull]::Value) {
            $def = $col.COLUMN_DEFAULT.ToString().Replace("'", "''")
            $colDef += " DEFAULT $def"
        }

        $columnDefs += $colDef
    }

    $sqlCreate = "CREATE TABLE [$tableName] (" + ($columnDefs -join ", ") + ");"

    # Validar y crear en cada base destino si no existe
    foreach ($destinoDB in $DatabasesDestino) {
        Write-Output "Verificando existencia en $destinoDB..."

        $existeTabla = Invoke-Sqlcmd -ServerInstance $ServerName -Username $Credential.Username `
                                     -Password $Credential.GetNetworkCredential().Password `
                                     -Database $destinoDB -Query "
            SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = '$tableName'
        "

        if ($existeTabla) {
            Write-Output "La tabla $tableName ya existe en $destinoDB. Saltando..."
            continue
        }

        Write-Output "Creando tabla $tableName en $destinoDB..."

       try {
            Invoke-Sqlcmd -ServerInstance $ServerName -Username $Credential.Username `
                        -Password $Credential.GetNetworkCredential().Password `
                        -Database $destinoDB -Query $sqlCreate -ErrorAction Stop
            Write-Output "Tabla $tableName creada exitosamente en $destinoDB"
        } catch {
            $mensajeError = $_.Exception.Message
            Write-Output ("Error creando " + $tableName + " en " + $destinoDB + ": " + $mensajeError)
        }
    }
}

Write-Output "Proceso finalizado."
