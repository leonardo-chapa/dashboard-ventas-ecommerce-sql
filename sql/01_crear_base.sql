-- =====================================================================
-- 01_crear_base.sql
-- Modelo limpio a partir de las tablas crudas (prefijo raw_).
-- Cada decisión de limpieza está comentada junto a la consulta que la aplica.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Categorías: el archivo de traducción no trae 2 categorías que sí
-- aparecen en productos, y 610 productos no tienen categoría.
-- La tabla categoria_es (cargada desde Python) da el nombre en español.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS productos;
CREATE TABLE productos AS
SELECT
    p.product_id                                   AS producto_id,
    COALESCE(c.categoria, 'Sin categoría')         AS categoria,
    p.product_weight_g                             AS peso_g
FROM raw_products p
LEFT JOIN categoria_es c
       ON c.categoria_pt = p.product_category_name;

-- ---------------------------------------------------------------------
-- Clientes: customer_id cambia en CADA pedido; la persona real es
-- customer_unique_id. Usar customer_id para medir recompra daría 0%.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS clientes;
CREATE TABLE clientes AS
SELECT
    customer_id          AS cliente_pedido_id,
    customer_unique_id   AS cliente_id,
    customer_state       AS estado
FROM raw_customers;

-- ---------------------------------------------------------------------
-- Pedidos: fechas a formato ISO y banderas de calidad, sin borrar filas.
--   * fecha_inconsistente: el transportista "recogió" antes de la compra,
--     o el cliente "recibió" antes de que lo recogiera el transportista.
--   * entregado_sin_fecha: status 'delivered' sin fecha de entrega.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS pedidos;
CREATE TABLE pedidos AS
SELECT
    o.order_id                                         AS pedido_id,
    o.customer_id                                      AS cliente_pedido_id,
    o.order_status                                     AS estatus,
    DATETIME(o.order_purchase_timestamp)               AS fecha_compra,
    STRFTIME('%Y-%m', o.order_purchase_timestamp)      AS mes,
    DATETIME(o.order_delivered_carrier_date)           AS fecha_envio,
    DATETIME(o.order_delivered_customer_date)          AS fecha_entrega,
    DATE(o.order_estimated_delivery_date)              AS fecha_estimada,
    CASE
        WHEN o.order_delivered_carrier_date < o.order_purchase_timestamp THEN 1
        WHEN o.order_delivered_customer_date < o.order_delivered_carrier_date THEN 1
        ELSE 0
    END                                                AS fecha_inconsistente,
    CASE WHEN o.order_status = 'delivered'
          AND o.order_delivered_customer_date IS NULL THEN 1 ELSE 0
    END                                                AS entregado_sin_fecha
FROM raw_orders o;

-- ---------------------------------------------------------------------
-- Partidas (una fila por artículo): ingreso = precio, sin flete.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS partidas;
CREATE TABLE partidas AS
SELECT
    order_id        AS pedido_id,
    order_item_id   AS partida,
    product_id      AS producto_id,
    seller_id       AS vendedor_id,
    price           AS precio,
    freight_value   AS flete
FROM raw_order_items;

-- ---------------------------------------------------------------------
-- Reseñas: hay pedidos con 2 o 3 reseñas. Se conserva la más reciente
-- por pedido para que cada pedido cuente una sola vez.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS resenas;
CREATE TABLE resenas AS
SELECT pedido_id, calificacion
FROM (
    SELECT
        order_id      AS pedido_id,
        review_score  AS calificacion,
        ROW_NUMBER() OVER (PARTITION BY order_id
                           ORDER BY review_answer_timestamp DESC,
                                    review_creation_date DESC) AS n
    FROM raw_order_reviews
)
WHERE n = 1;

-- ---------------------------------------------------------------------
-- Vista analítica: un pedido por fila, solo pedidos ENTREGADOS y de
-- meses completos (ene-2017 a ago-2018). Los meses de 2016 y de
-- sep/oct-2018 tienen muy pocos pedidos y distorsionarían las tendencias.
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS v_pedidos;
CREATE VIEW v_pedidos AS
SELECT
    p.pedido_id,
    c.cliente_id,
    c.estado,
    p.fecha_compra,
    p.mes,
    p.fecha_entrega,
    p.fecha_estimada,
    p.fecha_inconsistente,
    i.articulos,
    i.ingreso,
    i.flete,
    r.calificacion,
    JULIANDAY(p.fecha_entrega) - JULIANDAY(p.fecha_compra)          AS dias_entrega,
    CASE WHEN DATE(p.fecha_entrega) > p.fecha_estimada THEN 1 ELSE 0 END AS entrega_tardia
FROM pedidos p
JOIN clientes c USING (cliente_pedido_id)
JOIN (
    SELECT pedido_id, COUNT(*) AS articulos,
           SUM(precio) AS ingreso, SUM(flete) AS flete
    FROM partidas GROUP BY pedido_id
) i USING (pedido_id)
LEFT JOIN resenas r USING (pedido_id)
WHERE p.estatus = 'delivered'
  AND p.entregado_sin_fecha = 0
  AND p.mes BETWEEN '2017-01' AND '2018-08';
