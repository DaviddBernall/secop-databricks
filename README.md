# SECOP II: ingeniería de datos con Azure Databricks

Proyecto de ingeniería de datos para analizar la contratación de IDARTES e IDIPRON, con contratos de la cohorte 2024 y sus procesos asociados. Implementa una arquitectura medallion en Azure, con ingesta de datos públicos, tablas Delta administradas en Unity Catalog y visualización de indicadores.

## Resultados validados

El job de producción `job_secop_medallion_prod` (ID `20888432712983`) terminó correctamente. Las consultas posteriores en `project_prod` confirmaron estos conteos, coincidentes con desarrollo:

| Entidad | Contratos | Valor contratado, COP |
| --- | ---: | ---: |
| IDARTES | 3.651 | 129.817.001.887,89 |
| IDIPRON | 3.233 | 65.451.073.280,20 |
| Total | 6.884 | 195.268.075.168,09 |

Los valores monetarios fueron validados en desarrollo; en producción se verificaron los conteos de contratos y tablas Gold. El valor contratado es el valor publicado del contrato, no una medición de pagos o ejecución presupuestal.

| Tabla Gold | Filas verificadas en producción |
| --- | ---: |
| `kpi_contratacion_mensual` | 22 |
| `kpi_proveedores` | 4.231 |
| `kpi_modalidades` | 17 |
| `kpi_calidad_ingesta` | 2 |

## Arquitectura

![Arquitectura de datos y despliegue](docs/arquitectura.svg)

1. Azure Data Factory consume las APIs de SECOP II y conserva los archivos JSON en ADLS Gen2 Raw. El token de aplicación de Socrata se referencia desde Azure Key Vault.
2. Un notebook valida las páginas, los lotes y los conteos de los snapshots seleccionados.
3. Bronze registra los datos de origen y su trazabilidad en tablas Delta administradas.
4. Silver tipifica, depura y relaciona contratos, procesos y portafolios. Los contratos sin proceso encontrado se conservan.
5. Gold genera indicadores mensuales, de proveedores, modalidades y calidad de ingesta.
6. El dashboard consume las tablas Gold. Su acceso depende de los permisos del workspace y de Unity Catalog.

Las transformaciones se implementan en PySpark. SQL se utiliza para preparación, permisos, inspección y consultas de validación/visualización. No se utiliza DBFS ni un Volume como fuente de Raw.

## Ambientes

| Componente | Desarrollo | Producción |
| --- | --- | --- |
| Resource group | `rgsmartdatad01` | `rgsmartdatap01` |
| Storage account | `addb01` | `addbp01` |
| Catálogo | `project_dev` | `project_prod` |
| Raw | `abfss://raw@addb01.dfs.core.windows.net/` | `abfss://raw@addbp01.dfs.core.windows.net/` |
| Almacenamiento administrado del catálogo | `abfss://lakehouse@addb01.dfs.core.windows.net/` | `abfss://lakehouse@addbp01.dfs.core.windows.net/` |
| Job | `257900437343850` | `20888432712983` |

Los dos workspaces están asociados al mismo metastore. Los catálogos tienen almacenamiento propio y vinculaciones por ambiente; `project_prod` está aislado al workspace de producción. El contenedor `unit-catalog` corresponde a la raíz configurada del metastore; no es la ubicación de las tablas de estos catálogos.

Aunque se provisionaron contenedores Bronze, Silver y Gold, las tablas administradas utilizadas por el proyecto se almacenan en `lakehouse`, bajo rutas internas de Unity Catalog. Los esquemas lógicos no deben confundirse con contenedores físicos.

## Fuentes y alcance

Se utilizan dos datasets reales de SECOP II: contratos (`jbjy-vk9h`) y procesos (`p6dx-8zbt`). IDARTES e IDIPRON son las entidades seleccionadas dentro de esos datasets. Ver [fuentes, snapshots y calidad](datasets/README.md).

Para inicializar producción se copiaron desde desarrollo los archivos Raw ya auditados, conservando su jerarquía. La actividad de ADF reportó 186 archivos y 45.032.713 bytes tanto leídos como escritos, sin errores. Esto fue una inicialización mediante snapshot, no una nueva extracción de la API en producción. La salida de Copy indicó `NotVerified` para la verificación de consistencia; el conteo de bytes no debe presentarse como verificación criptográfica.

## Tablas

| Capa | Tablas |
| --- | --- |
| Bronze | `secop_contratos`, `secop_procesos` |
| Silver | `secop_contratos`, `secop_procesos`, `secop_portafolios` |
| Gold | `kpi_contratacion_mensual`, `kpi_proveedores`, `kpi_modalidades`, `kpi_calidad_ingesta` |

Las cargas incluyen identificadores de ejecución y controles de repetición. Bronze verifica la consistencia del snapshot antes de omitir una carga previamente registrada; Silver y Gold utilizan operaciones Delta de actualización/inserción. Estas garantías corresponden al alcance implementado y no sustituyen una estrategia general de CDC.

## Seguridad

- ADF utiliza identidad administrada para acceder al almacenamiento y permisos de lectura de secretos en Key Vault.
- Databricks accede a Raw mediante una storage credential basada en Access Connector e identidad administrada, gobernada por una external location.
- GitHub Actions utiliza federación OIDC para autenticarse en Databricks, sin almacenar un PAT de Databricks para el despliegue.
- La identidad de despliegue de producción es `sp-github-secop-prod`; la identidad de ejecución del job es `sp-secop-runtime-prod`.
- El runtime tiene lectura de Raw y permisos para crear tablas en los esquemas del proyecto. Las tablas creadas por esta identidad quedan bajo su propiedad.
- El acceso de lectura del usuario de validación se concede explícitamente; administrar el metastore no implica tener `SELECT` automático sobre cada tabla.
- La copia inicial utilizó temporalmente la identidad de ADF de dev con escritura sobre `raw` de prod. Esa asignación debe revisarse y retirarse cuando ya no sea necesaria; su retirada no se da por realizada en esta documentación.

Ver los scripts en [seguridad](seguridad/). No publicar tokens, secretos, archivos `.env` ni credenciales en el repositorio.

## Código y despliegue

El bundle se define en `databricks.yml` y el recurso del job en `resources/secop_medallion_job.yml`. Los notebooks ejecutables están en `proceso/`:

```text
00_validar_ingesta_procesos.ipynb
01_raw_a_bronze.ipynb
02_bronze_a_silver.ipynb
03_silver_a_gold.ipynb
```

El job encadena las cuatro tareas en ese orden. En prod utiliza un job cluster compartido, definido por el bundle y sujeto a la política de cómputo. El cluster de desarrollo se mantiene detenido cuando se ejecuta producción.

El flujo de trabajo utiliza ramas `feature/*` y pull requests; `dev` corresponde a desarrollo y `main` a la entrega de producción. Los workflows de `.github/workflows/` validan y despliegan el bundle. El despliegue de producción está condicionado a `main`.

**Límite actual de la automatización:** los workflows entregados despliegan el job, pero no ejecutan automáticamente el ETL. La ejecución de producción documentada se inició desde Databricks; la de desarrollo también se probó mediante ADF. La preparación del ambiente y los permisos se configuraron por separado y se documentan en SQL. No se afirma una automatización completa de preparación → ETL → permisos desde GitHub Actions.

## Cómo reproducir la ejecución

1. Provisionar el ambiente de Azure y configurar metastore, catálogo, almacenamiento administrado y external location con identidad administrada. Los SQL de `PrepAmb` no provisionan esos recursos de Azure.
2. Preparar los esquemas del catálogo en el workspace correspondiente, con una identidad autorizada. Consultar `PrepAmb/01_preparar_ambiente.sql` para producción.
3. Configurar los permisos de la identidad runtime y los permisos de despliegue/cómputo. Ver `seguridad/02_grants_runtime_prod.sql` y la configuración del bundle.
4. Ingestar los datasets en Raw con ADF, o inicializar el snapshot documentado preservando su jerarquía. No basta con copiar un archivo JSON aislado.
5. Configurar las variables de GitHub por ambiente, las políticas de federación OIDC y las variables del bundle. Revisar el plan antes de desplegar.
6. Desplegar desde la rama autorizada. Revisar que el `run_as`, los parámetros y el almacenamiento correspondan al ambiente elegido.
7. Ejecutar el job una sola vez con los parámetros del snapshot y esperar las cuatro tareas en `Succeeded`.
8. Aplicar los permisos de lectura necesarios y ejecutar [las consultas de validación](dashboard/validar_resultados_prod.sql).

### Parámetros del snapshot reproducido

| Parámetro | Producción |
| --- | --- |
| `ambiente` | `prod` |
| `catalogo` | `project_prod` |
| `storage_account` | `addbp01` |
| `anio` | `2024` |
| `run_idartes` | `95aa87aa-90ee-4104-8f38-d18edc3287b8` |
| `run_idipron` | `90a6911a-40da-486b-b7c4-9ac9ab37ecfa` |
| `run_procesos` | `6717455f-416d-4457-9a88-600732d976d6` |

Los IDs se mantienen en producción porque se preservaron las carpetas de los snapshots durante la copia inicial. Para una nueva extracción deben revisarse los parámetros y los controles de conteo; no se deben asumir los mismos resultados.

## Dashboard y evidencias

La visualización desarrollada utiliza las cuatro tablas Gold. Ver [documentación del dashboard](dashboard/README.md) y [enlace de acceso](dashboard/enlace.txt). Un dashboard privado no se vuelve público por publicar el repositorio.

Las evidencias se organizan en `evidencias/dev/`, `evidencias/prod/` y, cuando se incorporen, `evidencias/azure/`. Cada captura debe corresponder a una ejecución real. Ver [guía de evidencias](evidencias/README.md).

## Reversión y límites de la entrega

El procedimiento de [reversión](reversion/README.md) contiene SQL desactivado por defecto. No se ejecuta en el despliegue ni se utiliza para limpiar la entrega. La eliminación física de tablas administradas se delega al ciclo de vida de Unity Catalog; nunca se eliminan directamente sus directorios internos.

Los notebooks se entregan en formato `.ipynb`. No se incluyen exportaciones `.py` ni tareas nuevas de preparación/permisos en `proceso`. Esta decisión y la automatización parcial descrita arriba deben considerarse al contrastar la entrega con los requisitos académicos. Las certificaciones son un componente adicional, no un resultado técnico atribuido al proyecto.

## Referencias

- [SECOP II: contratos electrónicos](https://www.datos.gov.co/resource/jbjy-vk9h.json)
- [SECOP II: procesos de contratación](https://www.datos.gov.co/resource/p6dx-8zbt.json)
- [Configuración de bundles](https://learn.microsoft.com/en-us/azure/databricks/dev-tools/bundles/settings)
- [Privilegios en Unity Catalog](https://learn.microsoft.com/en-us/azure/databricks/data-governance/unity-catalog/manage-privileges/privileges)
- [Ciclo de vida del almacenamiento administrado](https://learn.microsoft.com/en-us/azure/databricks/data-governance/unity-catalog/object-storage-lifecycle)