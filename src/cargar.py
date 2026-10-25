"""Carga los CSV de Olist a SQLite y ejecuta los scripts SQL."""

from __future__ import annotations

import re
import sqlite3
from pathlib import Path

import pandas as pd

RAIZ = Path(__file__).resolve().parent.parent
CRUDOS = RAIZ / "datos_crudos"
BASE = RAIZ / "salida" / "olist.sqlite"

TABLAS = {
    "raw_orders": "olist_orders_dataset.csv",
    "raw_order_items": "olist_order_items_dataset.csv",
    "raw_order_payments": "olist_order_payments_dataset.csv",
    "raw_order_reviews": "olist_order_reviews_dataset.csv",
    "raw_customers": "olist_customers_dataset.csv",
    "raw_products": "olist_products_dataset.csv",
    "raw_sellers": "olist_sellers_dataset.csv",
}

# Conteos del dataset original publicado por Olist; si no coinciden, el archivo está incompleto
FILAS_ESPERADAS = {
    "raw_orders": 99_441, "raw_order_items": 112_650, "raw_order_payments": 103_886,
    "raw_order_reviews": 100_000, "raw_customers": 99_441, "raw_products": 32_951,
    "raw_sellers": 3_095,
}

# Nombres en español. Incluye las 2 categorías que faltan en el archivo de traducción.
CATEGORIAS_ES = {
    "beleza_saude": "Salud y belleza", "informatica_acessorios": "Accesorios de cómputo",
    "automotivo": "Automotriz", "cama_mesa_banho": "Blancos (cama, mesa y baño)",
    "moveis_decoracao": "Muebles y decoración", "esporte_lazer": "Deportes y ocio",
    "perfumaria": "Perfumería", "utilidades_domesticas": "Artículos para el hogar",
    "telefonia": "Telefonía celular", "relogios_presentes": "Relojes y regalos",
    "alimentos_bebidas": "Alimentos y bebidas", "bebes": "Bebés", "papelaria": "Papelería",
    "tablets_impressao_imagem": "Tabletas e impresión", "brinquedos": "Juguetes",
    "telefonia_fixa": "Telefonía fija", "ferramentas_jardim": "Herramientas de jardín",
    "fashion_bolsas_e_acessorios": "Bolsas y accesorios", "eletroportateis": "Electrodomésticos pequeños",
    "consoles_games": "Consolas y videojuegos", "audio": "Audio", "fashion_calcados": "Calzado",
    "cool_stuff": "Artículos novedosos", "malas_acessorios": "Maletas y accesorios",
    "climatizacao": "Aire acondicionado", "construcao_ferramentas_construcao": "Construcción",
    "moveis_cozinha_area_de_servico_jantar_e_jardim": "Muebles de cocina, comedor y jardín",
    "construcao_ferramentas_jardim": "Construcción: jardín", "fashion_roupa_masculina": "Ropa de hombre",
    "pet_shop": "Mascotas", "moveis_escritorio": "Muebles de oficina", "market_place": "Marketplace",
    "eletronicos": "Electrónica", "eletrodomesticos": "Electrodomésticos",
    "artigos_de_festas": "Artículos para fiestas", "casa_conforto": "Confort del hogar",
    "construcao_ferramentas_ferramentas": "Herramientas", "agro_industria_e_comercio": "Agroindustria",
    "moveis_colchao_e_estofado": "Colchones y tapicería", "livros_tecnicos": "Libros técnicos",
    "casa_construcao": "Construcción del hogar", "instrumentos_musicais": "Instrumentos musicales",
    "moveis_sala": "Muebles de sala", "construcao_ferramentas_iluminacao": "Iluminación",
    "industria_comercio_e_negocios": "Industria y comercio", "alimentos": "Alimentos", "artes": "Arte",
    "moveis_quarto": "Muebles de recámara", "livros_interesse_geral": "Libros de interés general",
    "construcao_ferramentas_seguranca": "Seguridad (construcción)",
    "fashion_underwear_e_moda_praia": "Ropa interior y de playa", "fashion_esporte": "Ropa deportiva",
    "sinalizacao_e_seguranca": "Señalización y seguridad", "pcs": "Computadoras",
    "artigos_de_natal": "Artículos navideños", "fashion_roupa_feminina": "Ropa de mujer",
    "eletrodomesticos_2": "Electrodomésticos (2)", "livros_importados": "Libros importados",
    "bebidas": "Bebidas", "cine_foto": "Cine y foto", "la_cuisine": "Cocina gourmet", "musica": "Música",
    "casa_conforto_2": "Confort del hogar (2)",
    "portateis_casa_forno_e_cafe": "Hornos y cafeteras", "cds_dvds_musicais": "CDs y DVDs musicales",
    "dvds_blu_ray": "DVD y Blu-ray", "flores": "Flores", "artes_e_artesanato": "Artesanías",
    "fraldas_higiene": "Pañales e higiene", "fashion_roupa_infanto_juvenil": "Ropa infantil",
    "seguros_e_servicos": "Seguros y servicios",
    "portateis_cozinha_e_preparadores_de_alimentos": "Procesadores de alimentos",
    "pc_gamer": "PC gamer",
}


def cargar(base: Path = BASE) -> sqlite3.Connection:
    base.parent.mkdir(parents=True, exist_ok=True)
    if base.exists():
        base.unlink()
    con = sqlite3.connect(base)
    for tabla, archivo in TABLAS.items():
        df = pd.read_csv(CRUDOS / archivo)
        if len(df) != FILAS_ESPERADAS[tabla]:
            raise ValueError(f"{archivo}: {len(df):,} filas, se esperaban {FILAS_ESPERADAS[tabla]:,}")
        df.to_sql(tabla, con, index=False)

    faltantes = set(pd.read_csv(CRUDOS / TABLAS["raw_products"]).product_category_name.dropna()) - set(CATEGORIAS_ES)
    if faltantes:
        raise ValueError(f"Categorías sin nombre en español: {faltantes}")
    pd.DataFrame(CATEGORIAS_ES.items(), columns=["categoria_pt", "categoria"]).to_sql("categoria_es", con, index=False)

    con.executescript((RAIZ / "sql" / "01_crear_base.sql").read_text(encoding="utf-8"))
    return con


def consultas(con: sqlite3.Connection) -> dict[str, pd.DataFrame]:
    """Ejecuta cada bloque '-- @nombre' de 02_analisis.sql."""
    texto = (RAIZ / "sql" / "02_analisis.sql").read_text(encoding="utf-8")
    bloques = re.split(r"^-- @(\w+)\s*$", texto, flags=re.M)[1:]
    return {nombre: pd.read_sql_query(sql, con) for nombre, sql in zip(bloques[::2], bloques[1::2])}
