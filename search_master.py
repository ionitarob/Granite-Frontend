
import os
import django
import sys

backend_path = r'c:\Users\rmaglan\Documents\CTool Granite\Granite-Backend\django_backend'
sys.path.append(backend_path)
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'django_backend.settings')
django.setup()

from django.db import connection

def search_description():
    term = 'MASTER'
    print(f"Searching for '{term}' in descriptions of [datapass].[administracion].[cotizaciones]...")
    
    with connection.cursor() as cur:
        query = """
            SELECT sku_config, sku_hp, sku_lenovo, description 
            FROM [datapass].[administracion].[cotizaciones] 
            WHERE description LIKE %s
        """
        pattern = f"%{term}%"
        cur.execute(query, [pattern])
        rows = cur.fetchall()
        if not rows:
            print("No matches.")
        for r in rows:
            print(f"Config={r[0]}, HP={r[1]}, Lenovo={r[2]}, Desc={r[3]}")

if __name__ == "__main__":
    search_description()
