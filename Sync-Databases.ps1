# --------------------------------------------
# Sincronizador de estructuras entre bases - JORGE CORAL TORRES 2025-05-22
# --------------------------------------------

# Importar el módulo SqlServer
Import-Module SqlServer

# Especificar los parámetros del script
$ServerName = "MI_URL_DE_AZURE"
$Credential = Get-AutomationPSCredential -Name "AzureSQL_Cred"

$OrigenDatabase = "MI_BASE_ORIGINAL"

# Base de datos principal (origen de referencia estructural)
$LogsDatabase = "BASE_DE_LOGS"

# Bases de datos destino donde se replicará la estructura
$DatabasesDestino = @(
    "BASE1","BASE2",...,"BASEN"
)

# Tablas a sincronizar (deben existir en la base de datos de origen y destino)
$TableList = @(
    "TABLA1", "TABLA2",...., "TABLAN"
)

foreach ($tableName in $TableList) {
    Write-Output "Procesando estructura de tabla: $tableName"

    $query = @"
    SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH,
           NUMERIC_PRECISION, NUMERIC_SCALE, IS_NULLABLE, COLUMN_DEFAULT
    FROM [$OrigenDatabase].INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_NAME = '$tableName'
    ORDER BY ORDINAL_POSITION
"@

    $estructuraOrigen = Invoke-Sqlcmd -ServerInstance $ServerName -Username $Credential.Username -Password $Credential.GetNetworkCredential().Password -Database $OrigenDatabase -Query $query
    if (-not $estructuraOrigen) {
        Write-Output "No se encontró estructura para $tableName en $OrigenDatabase"
        continue
    }

    $estructuraCampos = @{}
    foreach ($col in $estructuraOrigen) {
        $tipoDato = $col.DATA_TYPE

        if ($tipoDato -in @("varchar", "nvarchar", "char", "nchar", "binary", "varbinary")) {
            $longitud = $col.CHARACTER_MAXIMUM_LENGTH
            if ($longitud -eq -1) {
                $tipoDato += "(MAX)"
            } else {
                $tipoDato += "($longitud)"
            }
        } elseif ($tipoDato -in @("decimal", "numeric")) {
            $tipoDato += "($($col.NUMERIC_PRECISION),$($col.NUMERIC_SCALE))"
        }

        $estructuraCampos[$col.COLUMN_NAME] = @{
            Tipo = $tipoDato
            Null = $col.IS_NULLABLE
            Default = $col.COLUMN_DEFAULT
        }
    }

    foreach ($destinoDB in $DatabasesDestino) {
        Write-Output "Verificando en base: $destinoDB"

        $existeTabla = Invoke-Sqlcmd -ServerInstance $ServerName -Username $Credential.Username -Password $Credential.GetNetworkCredential().Password -Database $destinoDB -Query "SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = '$tableName'"
        if (-not $existeTabla) {
            Write-Output "Tabla $tableName NO existe en $destinoDB"
            continue
        }

        $queryDestino = "SELECT COLUMN_NAME FROM [$destinoDB].INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = '$tableName'"
        $camposDestino = Invoke-Sqlcmd -ServerInstance $ServerName -Username $Credential.Username -Password $Credential.GetNetworkCredential().Password -Database $destinoDB -Query $queryDestino | ForEach-Object { $_.COLUMN_NAME }

        foreach ($campo in $estructuraCampos.Keys) {
            if ($camposDestino -notcontains $campo) {
                $tipo = $estructuraCampos[$campo].Tipo
                $null = if ($estructuraCampos[$campo].Null -eq "YES") { "NULL" } else { "NOT NULL" }
				$default = $estructuraCampos[$campo].Default
				$defaultClause = ""
				if ($default -and $default -ne "NULL" -and $default -ne [DBNull]::Value) {
					$defaultStr = $default.ToString()
					$defaultClean = $defaultStr.Trim("(", ")").Replace("'", "''")
					$defaultClause = " DEFAULT $defaultClean"
				}
                $alterQuery = "ALTER TABLE [$tableName] ADD [$campo] $tipo $null$defaultClause;"
                Write-Output "Agregando campo $campo a $destinoDB.$tableName"

                try {
                    Invoke-Sqlcmd -ServerInstance $ServerName -Username $Credential.Username -Password $Credential.GetNetworkCredential().Password -Database $destinoDB -Query $alterQuery -ErrorAction Stop
                    Write-Output "Campo $campo agregado exitosamente."

                    $logQuery = @"
                    INSERT INTO $LogsDatabase.dbo.LOG_SYNC_DBS_COLUMNS (
                        BASE_DESTINO, NOMBRE_TABLA, NOMBRE_CAMPO, TIPO_DATO,
                        ES_NULLABLE, VALOR_DEFAULT, ACCION_REALIZADA, RESULTADO, FECHAEJECUCION
                    ) VALUES (
                        '$destinoDB', '$tableName', '$campo', '$tipo',
                        '$null', $(if ($default) { "'$($default -replace "'", "''")'" } else { "NULL" }),
                        'AGREGADO', 'Campo agregado exitosamente', GETDATE()
                    )
"@
                    Invoke-Sqlcmd -ServerInstance $ServerName -Username $Credential.Username -Password $Credential.GetNetworkCredential().Password -Database $LogsDatabase -Query $logQuery -ErrorAction Stop
                } catch {
                    $mensajeError = ($_.Exception.Message).Replace("'", "''")
                    Write-Output "ERROR al agregar campo: $mensajeError"

                    $logQuery = @"
                    INSERT INTO $LogsDatabase.dbo.LOG_SYNC_DBS_COLUMNS (
                        BASE_DESTINO, NOMBRE_TABLA, NOMBRE_CAMPO, TIPO_DATO,
                        ES_NULLABLE, VALOR_DEFAULT, ACCION_REALIZADA, RESULTADO, FECHAEJECUCION
                    ) VALUES (
                        '$destinoDB', '$tableName', '$campo', '$tipo',
                        '$null', $(if ($default) { "'$($default -replace "'", "''")'" } else { "NULL" }),
                        'ERROR', '$mensajeError', GETDATE()
                    )
"@
                    Invoke-Sqlcmd -ServerInstance $ServerName -Username $Credential.Username -Password $Credential.GetNetworkCredential().Password -Database $LogsDatabase -Query $logQuery -ErrorAction SilentlyContinue
                }
            }
        }
    }
} 

Write-Output "Proceso finalizado."
