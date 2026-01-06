<#
.SYNOPSIS
    Script Maestro de Scaffolding .NET 10 para múltiples proyectos y contextos.
    By: Erdu-EC
#>

$ErrorActionPreference = "Stop"

# --- CONFIGURACIÓN ---
$configFile = "scaffold.config.json"
$secretsFile = "scaffold.connections.config.json"
$provider = "Npgsql.EntityFrameworkCore.PostgreSQL"

# --- FUNCIONES ---

function Get-JsonConfig {
    param ( [string]$Path )
    if (-not (Test-Path $Path)) { throw "Archivo no encontrado: $Path" }
    try { return Get-Content $Path -Raw | ConvertFrom-Json }
    catch { throw "Error parseando JSON en: $Path" }
}

function Unlock-Files {
    param ( [string]$Path )
    if (-not (Test-Path $Path)) { return }
    $files = Get-ChildItem -Path $Path -Filter "*.cs" -Recurse
    foreach ($file in $files) {
        if ($file.IsReadOnly) { $file.IsReadOnly = $false }
    }
}

# --- INICIO DEL PROCESO ---
Write-Host "====================================" -ForegroundColor DarkGray
Write-Host "[INIT] Db Scaffolding System (By Erdu-EC)" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor DarkGray

try {
    $configs = Get-JsonConfig -Path $configFile
    $secrets = Get-JsonConfig -Path $secretsFile
}
catch {
    Write-Error $_
    exit 1
}

foreach ($cfg in $configs) {
    Write-Host "`n------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "[PROYECTO] $($cfg.name)" -ForegroundColor Yellow
    
    # 1. Validar Secretos
    $connString = $secrets.PSObject.Properties[$cfg.contextName].Value
    if ([string]::IsNullOrWhiteSpace($connString)) {
        Write-Error "   [X] FATAL: ConnectionString faltante para '$($cfg.contextName)'"
        continue
    }

    # 2. Rutas (CORRECCIÓN APLICADA AQUÍ)
    $baseScriptPath = $PSScriptRoot
    
    # A. Normalizamos la ruta del proyecto
    # Si projectPath incluye el archivo .csproj, sacamos solo el directorio.
    $projectRelPath = $cfg.projectPath
    if ($projectRelPath.EndsWith(".csproj")) {
        $projectRelPath = Split-Path $projectRelPath -Parent
    }

    # B. Construimos la ruta absoluta paso a paso
    # Paso 1: Ir a la carpeta del proyecto
    $absProjectDir = Join-Path $baseScriptPath $projectRelPath
    
    # Paso 2: Dentro del proyecto, ir al OutputDir
    $absOutputDir = Join-Path $absProjectDir $cfg.outputDir
    
    # IMPRIMIMOS LA RUTA PARA VERIFICAR
    Write-Host "   [DEBUG PATH] Ruta Real Entities:" -ForegroundColor Magenta
    Write-Host "       -> $absOutputDir" -ForegroundColor White

    # Pre-check
    if (-not (Test-Path $absOutputDir)) {
        Write-Warning "   [!] La carpeta no existe. Se creará automáticamente si EF Core tiene éxito."
    } else {
        Unlock-Files -Path $absOutputDir
    }

    # MARCA DE TIEMPO
    $startTime = (Get-Date).AddSeconds(-5)

    # 3. Argumentos
    $efArgs = @(
        "dbcontext", "scaffold", 
        $connString, 
        $provider,
        "--project", $cfg.projectPath,
        "--startup-project", $cfg.startupProject,
        "--output-dir", $cfg.outputDir,
        "--context-dir", $cfg.contextDir,
        "--context", $cfg.contextName,
        "--force",      
        "--no-build",
        "--no-onconfiguring"
    )

    Write-Host "`n   [PLAN] Configurando tablas..." -ForegroundColor Cyan
    
    # Filtros
    $tieneEsquemas = $false
    if ($cfg.PSObject.Properties.Match("schemas").Count -gt 0 -and $cfg.schemas -ne $null) {
        foreach ($prop in $cfg.schemas.PSObject.Properties) {
            $schemaName = $prop.Name
            [array]$tables = $prop.Value 
            $tieneEsquemas = $true

            if ($tables -and $tables.Count -gt 0) {
                foreach ($table in $tables) {
                    $efArgs += "--table", "$schemaName.$table"
                    Write-Host "     -> Tabla: $schemaName.$table" -ForegroundColor DarkGray
                }
            } else {
                $efArgs += "--schema", $schemaName
                Write-Host "     -> Esquema Completo: $schemaName" -ForegroundColor Magenta
            }
        }
    }

    # 4. Ejecución
    Write-Host "`n   [EXEC] Ejecutando EF Core..." -NoNewline -ForegroundColor Cyan
    
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = "dotnet"
    $pinfo.Arguments = "ef " + ($efArgs -join " ")
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true
    
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $pinfo
    
    try {
        $process.Start() | Out-Null
        $stderr = $process.StandardError.ReadToEnd()
        $stdout = $process.StandardOutput.ReadToEnd()
        $process.WaitForExit()

        if ($process.ExitCode -eq 0) {
            Write-Host " [OK]" -ForegroundColor Green
            
            # --- 5. REPORTE Y LIMPIEZA ---
            Write-Host "`n   [RESULTADOS] Analizando cambios en disco..." -ForegroundColor Green
            
            if (Test-Path $absOutputDir) {
                $allFiles = Get-ChildItem -Path $absOutputDir -Filter "*.cs" -Recurse
                $generatedCount = 0
                $deletedCount = 0
                
                foreach ($file in $allFiles) {
                    if ($file.Name -eq "$($cfg.contextName).cs") { continue }

                    # Verificamos fechas
                    if ($file.LastWriteTime -ge $startTime) {
                        Write-Host "     [+] $($file.Name)" -ForegroundColor Green
                        $generatedCount++
                    }
                    elseif ($file.LastWriteTime -lt $startTime) {
                        try {
                            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                            Write-Host "     [-] $($file.Name)" -ForegroundColor Red
                            $deletedCount++
                        }
                        catch {
                            Write-Warning "       [!] Error borrando $($file.Name)"
                        }
                    }
                }

                if ($generatedCount -eq 0 -and $deletedCount -eq 0) {
                     Write-Warning "     [!] No se detectaron cambios."
                }
            }
            else {
                Write-Error "     [ERROR] La carpeta sigue sin existir: $absOutputDir"
            }

        } else {
            Write-Host " [FALLO]" -ForegroundColor Red
            $cleanError = $stderr -split "`n" | Where-Object { $_ -notmatch "Microsoft.Extensions.Hosting" }
            Write-Host ($cleanError -join "`n") -ForegroundColor Red
        }
    }
    catch {
        Write-Error $_
    }
    
    Write-Host "`n------------------------------------------------------------" -ForegroundColor DarkGray
}
Write-Host "`n[DONE] Finalizado." -ForegroundColor Cyan