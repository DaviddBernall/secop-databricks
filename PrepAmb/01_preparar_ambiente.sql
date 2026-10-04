-- Preparación de los esquemas del ambiente de producción.
--
-- Prerrequisitos configurados previamente:
-- 1. Workspace de prod asociado al metastore.
-- 2. Catálogo project_prod vinculado al workspace de prod.
-- 3. Almacenamiento administrado del catálogo:
--    abfss://lakehouse@addbp01.dfs.core.windows.net/
-- 4. External location loc_raw_prod configurada mediante
--    Access Connector e identidad administrada.
--
-- Ejecutar con una identidad autorizada para crear esquemas.
-- No recrea el catálogo ni modifica su almacenamiento.
-- Las tablas Delta las crean los notebooks del ETL.

USE CATALOG project_prod;

CREATE SCHEMA IF NOT EXISTS project_prod.bronze
COMMENT 'Datos de origen con metadatos de ingesta y trazabilidad';

CREATE SCHEMA IF NOT EXISTS project_prod.silver
COMMENT 'Datos depurados, tipificados y relacionados';

CREATE SCHEMA IF NOT EXISTS project_prod.gold
COMMENT 'Indicadores de contratación para análisis y dashboard';

-- Comprobación de los esquemas disponibles.
SHOW SCHEMAS IN project_prod;