
import os
import django
import sys

backend_path = r'c:\Users\rmaglan\Documents\CTool Granite\Granite-Backend\django_backend'
sys.path.append(backend_path)
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'django_backend.settings')
django.setup()

from django.db import connection

def deep_search():
    skus = ['CP46088', 'CM58712', 'CL67637', 'CQ20331', '291910811']
    print(f"Searching for SKUs in [datapass].[administracion].[cotizaciones]: {skus}")
    
    with connection.cursor() as cur:
        for s in skus:
            print(f"\n--- Results for {s} ---")
            query = """
                SELECT id, sku_config, sku_hp, sku_lenovo, description 
                FROM [datapass].[administracion].[cotizaciones] 
                WHERE sku_config LIKE %s 
                   OR sku_hp LIKE %s 
                   OR sku_lenovo LIKE %s 
                   OR description LIKE %s
            """
            pattern = f"%{s}%"
            cur.execute(query, [pattern, pattern, pattern, pattern])
            rows = cur.fetchall()
            if not rows:
                print("No matches.")
            for r in rows:
                print(f"ID={r[0]}, Config={r[1]}, HP={r[2]}, Lenovo={r[3]}, Desc={r[4]}")

if __name__ == "__main__":
    deep_search()
