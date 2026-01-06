# Dotnet Db Scaffold PowerShell Wrapper

Automatiza el `dotnet ef dbcontext scaffold` para múltiples proyectos y contextos desde un único script (`db-scaffold-runner.ps1`). Está pensado para equipos que necesitan regenerar entidades de Entity Framework Core en diferentes soluciones manteniendo la configuración versionada.

## Requisitos previos
- PowerShell 5.1+ (o PowerShell 7+).
- .NET SDK 8/9/10 instalado y accesible en la variable `PATH`.
- Herramienta `dotnet-ef` instalada globalmente:
  ```powershell
  dotnet tool install --global dotnet-ef
  ```
- Proveedor EF Core soportado. El script usa por defecto `Npgsql.EntityFrameworkCore.PostgreSQL`; ajusta `$provider` dentro del script si necesitas otro proveedor.

## Archivos de configuración
### `scaffold.config.json`
Lista los proyectos que se van a escaffoldear. Cada objeto representa un contexto. Campos disponibles:

| Campo | Descripción |
| --- | --- |
| `name` | Etiqueta amigable que se mostrará en la salida del script. |
| `projectPath` | Ruta relativa al `.csproj` o a la carpeta del proyecto que contiene la capa de infraestructura. |
| `startupProject` | Ruta relativa al proyecto que contiene las dependencias de inicio para EF Core (por ejemplo la API). |
| `outputDir` | Carpeta (dentro de `projectPath`) donde se depositarán las entidades generadas. |
| `contextDir` | Carpeta donde se ubica el archivo del `DbContext`. |
| `contextName` | Nombre del contexto que se regenerará. Debe coincidir con la clave en `scaffold.connections.config.json`. |
| `schemas` | Objeto cuyos nombres son esquemas de base de datos. Cada esquema acepta un arreglo de tablas específicas. Dejar el arreglo vacío (`[]`) escaffoldeará todo el esquema completo. |

Ejemplo:
```json
[
  {
    "name": "API A",
    "projectPath": "src/A.Infrastructure",
    "startupProject": "src/A.Api",
    "outputDir": "Database/Entities/Generated",
    "contextDir": "Database/Context",
    "contextName": "DefaultDbContext",
    "schemas": {
      "public": ["users", "orders"],
      "audit": []
    }
  }
]
```

### `scaffold.connections.config.json`
Define las cadenas de conexión usadas por cada contexto. Las claves deben coincidir con `contextName` y los valores pueden ser cadenas completas o referencias (`Name=`) a la configuración de tu `appsettings.json`.

```json
{
  "DefaultDbContext": "Host=my_host;Port=5432;Database=my_db;Username=my_user;Password=my_password;",
  "NamedDbContext": "Name=ConnectionStrings:MyDb"
}
```
> **Tip:** No comprometas credenciales reales. Usa secretos de entorno, `dotnet user-secrets` o variables de CI/CD para generar el archivo antes de ejecutar el script.

## Cómo usar el script
1. Clona o descarga este repositorio.
2. Ajusta `scaffold.config.json` y `scaffold.connections.config.json` según tus proyectos.
3. Desde la raíz del repo ejecuta:
   ```powershell
   .\db-scaffold-runner.ps1
   ```
4. El script recorrerá cada entrada, desbloqueará los archivos generados previamente y ejecutará `dotnet ef dbcontext scaffold` con los filtros definidos en `schemas`.
5. Revisa el resumen: muestra archivos generados (`[+]`), eliminados (`[-]`) o advierte si no hubo cambios.

> **Nota:** Cada vez que se ejecuta el proceso se eliminan todos los `.cs` dentro de cada `outputDir` configurado (excepto el archivo del `DbContext`) antes de regenerarlos, para evitar residuos de entidades antiguas.

## Personalización
- **Proveedor diferente:** edita la variable `$provider` en `db-scaffold-runner.ps1` (por ejemplo `Microsoft.EntityFrameworkCore.SqlServer`).
- **Construcción previa:** quita `--no-build` de `$efArgs` si necesitas compilar antes de cada scaffolding.
- **OnConfiguring:** elimina `--no-onconfiguring` para que EF genere la sección `OnConfiguring` en el contexto.

## Resolución de problemas
- `ConnectionString faltante`: asegúrate de que cada `contextName` tenga entrada en `scaffold.connections.config.json`.
- `dotnet-ef` no encontrado: instala la herramienta global o agrega `%USERPROFILE%\.dotnet\tools` al `PATH`.
- Rutas inválidas (`projectPath`/`startupProject`): comprueba que sean relativas al script y que existan los `.csproj`.
- Sin cambios detectados: verifica filtros `schemas` y que la base de datos tenga tablas dentro del rango solicitado.
- Archivos de sólo lectura: el script intenta desbloquear `.cs` en el `outputDir`; si usas control de código fuente, asegúrate de tener permisos de escritura.

## Licencia
Este proyecto se distribuye bajo la licencia incluida en `LICENSE`. Ajusta o reutiliza el script según tus necesidades.
