"""Ejecuta todo el proyecto: carga a SQLite, consultas SQL y dashboard en Excel."""
import sys
sys.path.insert(0, "src")

from cargar import cargar, consultas
from dashboard import construir

con = cargar()
resultados = consultas(con)
for nombre, tabla in resultados.items():
    tabla.to_csv(f"salida/{nombre}.csv", index=False, encoding="utf-8-sig")
construir(resultados, "salida/dashboard_ventas_olist.xlsx")
print("Listo: salida/olist.sqlite, salida/dashboard_ventas_olist.xlsx y los CSV de cada consulta")
