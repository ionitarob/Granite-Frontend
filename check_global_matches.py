
import os
import django
import sys

backend_path = r'c:\Users\rmaglan\Documents\CTool Granite\Granite-Backend\django_backend'
sys.path.append(backend_path)
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'django_backend.settings')
django.setup()

from django.db import connection

def check_global_matches():
    print("Checking for ANY matches between tbl_ConfigOrderLine and cotizaciones...")
    with connection.cursor() as cur:
        query = """
            SELECT TOP 20 l.SKU, c.sku_config, c.sku_hp, c.sku_lenovo, l.parent_idnbr
            FROM dbo.tbl_ConfigOrderLine l
            JOIN [datapass].[administracion].[cotizaciones] c ON (
                l.SKU = c.sku_config OR 
                l.SKU = c.sku_hp OR 
                l.SKU = c.sku_lenovo
            )
        """
        cur.execute(query)
        rows = cur.fetchall()
        if not rows:
            print("NO GLOBAL MATCHES FOUND AT ALL.")
        for r in rows:
            print(f"Match! SKU={r[0]}, Config={r[1]}, HP={r[2]}, Lenovo={r[3]}, OrderID={r[4]}")

if __name__ == "__main__":
    check_global_matches()
