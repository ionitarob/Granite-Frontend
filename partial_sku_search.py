
import os
import django
import sys

backend_path = r'c:\Users\rmaglan\Documents\CTool Granite\Granite-Backend\django_backend'
sys.path.append(backend_path)
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'django_backend.settings')
django.setup()

from django.db import connection

def partial_search():
    nums = ['46088', '58712', '67637', '20331']
    print(f"Searching for Numeric SKU parts in [datapass].[administracion].[cotizaciones]: {nums}")
    
    with connection.cursor() as cur:
        for n in nums:
            print(f"\n--- Results for %{n}% ---")
            query = """
                SELECT sku_config, sku_hp, sku_lenovo, description 
                FROM [datapass].[administracion].[cotizaciones] 
                WHERE sku_config LIKE %s 
                   OR sku_hp LIKE %s 
                   OR sku_lenovo LIKE %s
            """
            pattern = f"%{n}%"
            cur.execute(query, [pattern, pattern, pattern])
            rows = cur.fetchall()
            if not rows:
                print("No matches.")
            for r in rows:
                print(f"Config={r[0]}, HP={r[1]}, Lenovo={r[2]}, Desc={r[3]}")

if __name__ == "__main__":
    partial_search()
