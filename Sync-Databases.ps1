# --------------------------------------------
# Sincronizador de estructuras entre bases - JORGE CORAL TORRES 20225-05-22
# --------------------------------------------

# Importar el módulo SqlServer
Import-Module SqlServer

# Especificar los parámetros del script
$ServerName = "MI_URL_DE_AZURE"
$Credential = Get-AutomationPSCredential -Name "AzureSQL_Cred"

# Base de datos principal (origen de referencia estructural)
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

# Abrimos ciclo principal por cada tabla a sincronizar en base de datos origen
foreach ($tableName in $TableList) {
	Write-Output "Procesando estructura de tabla: $tableName"

	# Consulta para extraer columnas de la tabla actual en la base origen
	$query = @"
	SELECT 
		COLUMN_NAME,
		DATA_TYPE,
		CHARACTER_MAXIMUM_LENGTH,
		IS_NULLABLE,
		COLUMN_DEFAULT
	FROM [$OrigenDatabase].INFORMATION_SCHEMA.COLUMNS
	WHERE TABLE_NAME = '$tableName'
	ORDER BY ORDINAL_POSITION
	"@

	# Ejecutar la consulta para obtener metadatos de columnas
	$estructuraOrigen = Invoke-Sqlcmd -ServerInstance $ServerName -Username $Credential.Username -Password $Credential.GetNetworkCredential().Password -Database $OrigenDatabase -Query $query

	if (-not $estructuraOrigen) {
		Write-Output "No se encontró estructura para la tabla $tableName en $OrigenDatabase"
		continue
	}

	# Crear hashtable para esta tabla (campos como claves)
	$estructuraCampos = @{}

	foreach ($col in $estructuraOrigen) {
		# Tipo base
		$tipoDato = $col.DATA_TYPE

		# Tipos con longitud (ej: varchar(100))
		if ($tipoDato -in @("varchar", "nvarchar", "char", "nchar", "binary", "varbinary")) {
			$longitud = $col.CHARACTER_MAXIMUM_LENGTH
			if ($longitud -eq -1) {
				$tipoDato += "(MAX)"
			} else {
				$tipoDato += "($longitud)"
			}
		}

		# Tipos con precisión y escala (ej: decimal(18,2))
		elseif ($tipoDato -in @("decimal", "numeric")) {
			$precision = $col.NUMERIC_PRECISION
			$scale = $col.NUMERIC_SCALE
			$tipoDato += "($precision,$scale)"
		}

		# Cargar al hashtable
		$estructuraCampos[$col.COLUMN_NAME] = @{
			Tipo = $tipoDato
			Null = $col.IS_NULLABLE
			Default = $col.COLUMN_DEFAULT
		}
	}

	Write-Output "Campos extraídos de $tableName:"
	$estructuraCampos.Keys | ForEach-Object { Write-Output "  - $_ : $($estructuraCampos[$_].Tipo)" }

	# Aquí seguimos con la comparación con bases de datos destino
	# Recorrer cada base de datos destino
	foreach ($destinoDB in $DatabaseDestinos.Keys) {
		Write-Output "Verificando en base: $destinoDB"

		# Verificar si la tabla existe en la base destino
		$existeTablaSQL = @"
			SELECT 1 
			FROM INFORMATION_SCHEMA.TABLES 
			WHERE TABLE_NAME = '$tableName'
		"@
		
		#Ejecutamos la validacion de existencia de tabla
		$existeTabla = Invoke-Sqlcmd -ServerInstance $ServerName -Username $Credential.Username -Password $Credential.GetNetworkCredential().Password -Database $destinoDB -Query $existeTablaSQL

		if (-not $existeTabla) {
			Write-Output "Tabla $tableName NO existe en $destinoDB"
			continue
		}

		# Extraer campos existentes en la base destino para esta tabla
		$queryDestino = @"
			SELECT COLUMN_NAME
			FROM [$destinoDB].INFORMATION_SCHEMA.COLUMNS
			WHERE TABLE_NAME = '$tableName'
			"@

		$camposDestino = Invoke-Sqlcmd -ServerInstance $ServerName -Username $Credential.Username -Password $Credential.GetNetworkCredential().Password -Database $destinoDB -Query $queryDestino |
						 ForEach-Object { $_.COLUMN_NAME }

		# Comparar campos: identificar cuáles faltan
		foreach ($campo in $estructuraCampos.Keys) {
			if ($camposDestino -notcontains $campo) {
				$tipo = $estructuraCampos[$campo].Tipo
				$null = if ($estructuraCampos[$campo].Null -eq "YES") { "NULL" } else { "NOT NULL" }
				$default = $estructuraCampos[$campo].Default

				$defaultClause = ""
				if ($default -and $default -ne "NULL") {
					$defaultClean = $default.Trim("(", ")") # SQL devuelve con paréntesis a veces
					$defaultClause = " DEFAULT $defaultClean"
				}

				# Generar sentencia ALTER TABLE
				$alterQuery = "ALTER TABLE [$tableName] ADD [$campo] $tipo $null$defaultClause;"

				Write-Output "!!!Campo faltante en $destinoDB.$tableName -> $campo"
				Write-Output "Ejecutando: $alterQuery"

				try {
					Invoke-Sqlcmd -ServerInstance $ServerName -Username $Credential.Username -Password $Credential.GetNetworkCredential().Password -Database $destinoDB -Query $alterQuery -ErrorAction Stop
					Write-Output "Campo $campo agregado exitosamente en $destinoDB.$tableName"

					$logQuery = @"
					INSERT INTO basicosrama.dbo.LOG_SYNC_DBS_COLUMNS (
						BASE_DESTINO, NOMBRE_TABLA, NOMBRE_CAMPO, TIPO_DATO,
						ES_NULLABLE, VALOR_DEFAULT, ACCION_REALIZADA, RESULTADO, FECHAEJECUCION
					)
					VALUES (
						'$destinoDB',
						'$tableName',
						'$campo',
						'$($estructuraCampos[$campo].Tipo)',
						'$($estructuraCampos[$campo].Null)',
						$(if ($estructuraCampos[$campo].Default -ne $null) { "'$($estructuraCampos[$campo].Default -replace "'", "''")'" } else { "NULL" }),
						'AGREGADO',
						'Campo agregado exitosamente',
						GETDATE()
					)
				"@
					Invoke-Sqlcmd -ServerInstance $ServerName -Username $Credential.Username -Password $Credential.GetNetworkCredential().Password -Database $LogsDatabase -Query $logQuery -ErrorAction Stop
					Write-Output "Log registrado en tabla LOG_SYNC_DBS_COLUMNS (estado: AGREGADO)"
				}
				catch {
					$mensajeError = ($_.Exception.Message).Replace("'", "''")
					Write-Output "X - Error al agregar $campo en $destinoDB.$tableName: $mensajeError"

					$logQuery = @"
					INSERT INTO basicosrama.dbo.LOG_SYNC_DBS_COLUMNS (
						BASE_DESTINO, NOMBRE_TABLA, NOMBRE_CAMPO, TIPO_DATO,
						ES_NULLABLE, VALOR_DEFAULT, ACCION_REALIZADA, RESULTADO, FECHAEJECUCION
					)
					VALUES (
						'$destinoDB',
						'$tableName',
						'$campo',
						'$($estructuraCampos[$campo].Tipo)',
						'$($estructuraCampos[$campo].Null)',
						$(if ($estructuraCampos[$campo].Default) { "'$($estructuraCampos[$campo].Default -replace "'", "''")'" } else { "NULL" }),
						'ERROR',
						'$mensajeError',
						GETDATE()
					)
				"@
					Invoke-Sqlcmd -ServerInstance $ServerName -Username $Credential.Username -Password $Credential.GetNetworkCredential().Password -Database $LogsDatabase -Query $logQuery -ErrorAction SilentlyContinue
					Write-Output "Log registrado en tabla LOG_SYNC_DBS_COLUMNS (estado: ERROR)"
				}
			}
		}
	}	

}
