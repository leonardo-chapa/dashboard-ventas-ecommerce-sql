-- =====================================================================
-- 02_analisis.sql
-- Consultas de negocio. Cada bloque empieza con "-- @nombre" para que
-- Python lo ejecute y exporte el resultado a su propia hoja de Excel.
-- =====================================================================

-- @kpis
-- Indicadores generales del periodo ene-2017 a ago-2018.
SELECT
    COUNT(*)                                        AS pedidos,
    COUNT(DISTINCT cliente_id)                      AS clientes,
    ROUND(SUM(ingreso), 2)                          AS ingreso_brl,
    ROUND(AVG(ingreso), 2)                          AS ticket_promedio_brl,
    ROUND(AVG(dias_entrega), 1)                     AS dias_entrega_promedio,
    ROUND(100.0 * AVG(entrega_tardia), 1)           AS pct_entregas_tardias,
    ROUND(AVG(calificacion), 2)                     AS calificacion_promedio
FROM v_pedidos;

-- @ventas_mensuales
-- Ingreso y pedidos por mes, con crecimiento contra el mes anterior.
SELECT
    mes,
    COUNT(*)                                        AS pedidos,
    ROUND(SUM(ingreso), 2)                          AS ingreso_brl,
    ROUND(AVG(ingreso), 2)                          AS ticket_promedio_brl,
    ROUND(100.0 * (SUM(ingreso) - LAG(SUM(ingreso)) OVER (ORDER BY mes))
          / LAG(SUM(ingreso)) OVER (ORDER BY mes), 1) AS crecimiento_pct
FROM v_pedidos
GROUP BY mes
ORDER BY mes;

-- @categorias
-- Las 15 categorías con más ingreso y su participación acumulada (Pareto).
WITH por_cat AS (
    SELECT pr.categoria,
           COUNT(DISTINCT pa.pedido_id) AS pedidos,
           SUM(pa.precio)               AS ingreso
    FROM partidas pa
    JOIN v_pedidos v  USING (pedido_id)
    JOIN productos pr USING (producto_id)
    GROUP BY pr.categoria
)
SELECT
    categoria,
    pedidos,
    ROUND(ingreso, 2)                                              AS ingreso_brl,
    ROUND(100.0 * ingreso / SUM(ingreso) OVER (), 1)               AS pct_ingreso,
    ROUND(100.0 * SUM(ingreso) OVER (ORDER BY ingreso DESC)
          / SUM(ingreso) OVER (), 1)                               AS pct_acumulado
FROM por_cat
ORDER BY ingreso DESC
LIMIT 15;

-- @entrega_vs_calificacion
-- ¿Cómo cambia la calificación según el retraso respecto a la fecha prometida?
SELECT
    CASE
        WHEN JULIANDAY(DATE(fecha_entrega)) - JULIANDAY(fecha_estimada) <= -7 THEN '1. 7+ días antes'
        WHEN JULIANDAY(DATE(fecha_entrega)) - JULIANDAY(fecha_estimada) <= 0  THEN '2. A tiempo (0-6 días antes)'
        WHEN JULIANDAY(DATE(fecha_entrega)) - JULIANDAY(fecha_estimada) <= 7  THEN '3. 1-7 días tarde'
        ELSE '4. Más de 7 días tarde'
    END                                             AS rango_entrega,
    COUNT(*)                                        AS pedidos,
    ROUND(AVG(calificacion), 2)                     AS calificacion_promedio,
    ROUND(100.0 * AVG(calificacion <= 2), 1)        AS pct_calif_1_o_2
FROM v_pedidos
WHERE calificacion IS NOT NULL
  AND fecha_inconsistente = 0
GROUP BY rango_entrega
ORDER BY rango_entrega;

-- @estados
-- Ingreso, tiempo de entrega y retrasos por estado del cliente.
SELECT
    estado,
    COUNT(*)                                        AS pedidos,
    ROUND(SUM(ingreso), 2)                          AS ingreso_brl,
    ROUND(AVG(dias_entrega), 1)                     AS dias_entrega_promedio,
    ROUND(100.0 * AVG(entrega_tardia), 1)           AS pct_entregas_tardias,
    ROUND(AVG(calificacion), 2)                     AS calificacion_promedio
FROM v_pedidos
WHERE fecha_inconsistente = 0
GROUP BY estado
ORDER BY ingreso_brl DESC;

-- @recompra
-- Clientes por número de pedidos: ¿cuántos vuelven a comprar?
WITH por_cliente AS (
    SELECT cliente_id, COUNT(*) AS n_pedidos, SUM(ingreso) AS gasto
    FROM v_pedidos GROUP BY cliente_id
)
SELECT
    CASE WHEN n_pedidos >= 3 THEN '3 o más' ELSE CAST(n_pedidos AS TEXT) END AS pedidos_por_cliente,
    COUNT(*)                                             AS clientes,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)   AS pct_clientes,
    ROUND(AVG(gasto), 2)                                 AS gasto_promedio_brl
FROM por_cliente
GROUP BY pedidos_por_cliente
ORDER BY pedidos_por_cliente;

-- @calidad
-- Resumen de los problemas encontrados en los datos crudos.
SELECT 'Pedidos en el archivo original' AS concepto, COUNT(*) AS registros FROM raw_orders
UNION ALL SELECT 'Pedidos sin artículos (cancelados o no disponibles)',
       COUNT(*) FROM pedidos WHERE pedido_id NOT IN (SELECT pedido_id FROM partidas)
UNION ALL SELECT 'Pedidos "entregados" sin fecha de entrega', SUM(entregado_sin_fecha) FROM pedidos
UNION ALL SELECT 'Pedidos con fechas inconsistentes', SUM(fecha_inconsistente) FROM pedidos
UNION ALL SELECT 'Pedidos con más de una reseña',
       COUNT(*) FROM (SELECT order_id FROM raw_order_reviews GROUP BY order_id HAVING COUNT(*) > 1)
UNION ALL SELECT 'Productos sin categoría',
       COUNT(*) FROM raw_products WHERE product_category_name IS NULL
UNION ALL SELECT 'IDs de cliente por pedido (customer_id)', COUNT(DISTINCT customer_id) FROM raw_customers
UNION ALL SELECT 'Clientes reales (customer_unique_id)', COUNT(DISTINCT customer_unique_id) FROM raw_customers
UNION ALL SELECT 'Pedidos analizados (entregados, ene-2017 a ago-2018)', COUNT(*) FROM v_pedidos;
