# Script V15 2025/05/23

# Importar el módulo SqlServer
Import-Module SqlServer

# Especificar los parámetros del script
$ServerName = "MI_SERVIDOR_SQL"
$Credential = Get-AutomationPSCredential -Name "MI_CREDENCIAL_AUTOMATION"

# Crear un array con los nombres de las bases de datos
$DatabasesDestino = @("BASE1","BASE2",...,"BASEN")

# Crear un array con los nombres de las bases de datos
$excludedTable ="TABLA_EXCLUIDA"

# Umbrales de fragmentación - desde que valor se ejecuta
$UmbralReorganize = 5
$UmbralRebuild = 30

# Recorrer el array de bases de datos
foreach ($DatabaseName in $DatabaseNames) {
    try {
        Write-Output ("========================================")
        Write-Output ("Procesando base de datos: {0}" -f $DatabaseName)
        Write-Output ("========================================")

        $Sql = "SELECT TABLE_SCHEMA, TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE'"
        $Tables = Invoke-Sqlcmd -ServerInstance $ServerName -Username $Credential.Username -Password $Credential.GetNetworkCredential().Password -Database $DatabaseName -Query $Sql

        foreach ($Table in $Tables) {
            if ($Table.TABLE_NAME -ne $excludedTable) {
                Write-Output ("----------------------------------------")
                Write-Output ("Tabla: {0}.{1}" -f $Table.TABLE_SCHEMA, $Table.TABLE_NAME)
                Write-Output ("----------------------------------------")

                try {
                    $Sql = @"
SELECT I.name AS INDEX_NAME, DDIPS.avg_fragmentation_in_percent
FROM sys.dm_db_index_physical_stats (DB_ID(), OBJECT_ID('$($Table.TABLE_SCHEMA).$($Table.TABLE_NAME)'), NULL, NULL, NULL) AS DDIPS
INNER JOIN sys.indexes I ON I.object_id = DDIPS.object_id AND I.index_id = DDIPS.index_id
WHERE I.name IS NOT NULL AND DDIPS.avg_fragmentation_in_percent > 0
ORDER BY DDIPS.avg_fragmentation_in_percent DESC;
"@

                    $Indexes = Invoke-Sqlcmd -ServerInstance $ServerName -Username $Credential.Username -Password $Credential.GetNetworkCredential().Password -Database $DatabaseName -Query $Sql

                    if ($Indexes.Count -gt 0) {
                        Write-Output ("Índices fragmentados encontrados: {0}" -f $Indexes.Count)
                        foreach ($Index in $Indexes) {
                            $frag = [double]$Index.avg_fragmentation_in_percent
                            Write-Output (" - Índice: {0}, Fragmentación: {1}%" -f $Index.INDEX_NAME, $frag)

                            try {
                                if ($frag -ge $UmbralRebuild) {
                                    $Sql = "ALTER INDEX [$($Index.INDEX_NAME)] ON $($Table.TABLE_SCHEMA).$($Table.TABLE_NAME) REBUILD"
                                    Write-Output ("REBUILD de índice: {0}" -f $Index.INDEX_NAME)
                                } elseif ($frag -ge $UmbralReorganize) {
                                    $Sql = "ALTER INDEX [$($Index.INDEX_NAME)] ON $($Table.TABLE_SCHEMA).$($Table.TABLE_NAME) REORGANIZE"
                                    Write-Output ("REORGANIZE de índice: {0}" -f $Index.INDEX_NAME)
                                } else {
                                    continue
                                }

                                Invoke-Sqlcmd -ServerInstance $ServerName -Username $Credential.Username -Password $Credential.GetNetworkCredential().Password -Database $DatabaseName -Query $Sql
                                Write-Output ("Acción completada sobre el índice: {0}" -f $Index.INDEX_NAME)
                            } catch {
                                $ErrorMessage = "Error en índice {0} en {1}.{2}: {3}" -f $Index.INDEX_NAME, $Table.TABLE_SCHEMA, $Table.TABLE_NAME, $_.Exception.Message
                                Write-Error $ErrorMessage
                            }
                        }
                    } else {
                        Write-Output ("No se encontraron índices fragmentados en esta tabla.")
                    }
                } catch {
                    $ErrorMessage = "Error al obtener índices de {0}.{1} en {2}: {3}" -f $Table.TABLE_SCHEMA, $Table.TABLE_NAME, $DatabaseName, $_.Exception.Message
                    Write-Error $ErrorMessage
                }
            }
        }

        Write-Output ("Fin del procesamiento de la base de datos: {0}" -f $DatabaseName)
    } catch {
        $ErrorMessage = "Error general al procesar {0}: {1}" -f $DatabaseName, $_.Exception.Message
        Write-Error $ErrorMessage
    }
}

# Limpieza final
$DatabaseNames = $null
$Credential = $null
[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()
