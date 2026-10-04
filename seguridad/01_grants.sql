-- Acceso de lectura para validar los resultados de producción.
-- Ejecutar como administrador del metastore o con autoridad
-- para conceder permisos sobre estos objetos.
-- No cambia propietarios ni concede permisos de escritura.

GRANT USE CATALOG ON CATALOG project_prod
TO `lsb.davidbernal@gmail.com`;

GRANT USE SCHEMA ON SCHEMA project_prod.silver
TO `lsb.davidbernal@gmail.com`;

GRANT USE SCHEMA ON SCHEMA project_prod.gold
TO `lsb.davidbernal@gmail.com`;

GRANT SELECT ON TABLE project_prod.silver.secop_contratos
TO `lsb.davidbernal@gmail.com`;

GRANT SELECT ON TABLE project_prod.gold.kpi_contratacion_mensual
TO `lsb.davidbernal@gmail.com`;

GRANT SELECT ON TABLE project_prod.gold.kpi_proveedores
TO `lsb.davidbernal@gmail.com`;

GRANT SELECT ON TABLE project_prod.gold.kpi_modalidades
TO `lsb.davidbernal@gmail.com`;

GRANT SELECT ON TABLE project_prod.gold.kpi_calidad_ingesta
TO `lsb.davidbernal@gmail.com`;