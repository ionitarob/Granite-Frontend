
import os
import django
import sys

backend_path = r'c:\Users\rmaglan\Documents\CTool Granite\Granite-Backend\django_backend'
sys.path.append(backend_path)
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'django_backend.settings')
django.setup()

from django.db import connection

def test_sql(idnbr):
    sql = """
        SELECT DISTINCT
            c.id, c.family, c.description, c.extra_info_1, c.sku_config, 
            c.coste, c.pvd, c.margen, c.tiempo_min, c.personal, c.collection_info,
            l.UNIT_PRICE, l.SKU
        FROM dbo.tbl_ConfigOrderLine l
        JOIN [datapass].[administracion].[cotizaciones] c ON (
            l.SKU = c.sku_config OR 
            l.SKU = c.sku_hp OR 
            l.SKU = c.sku_lenovo
        )
        WHERE l.parent_idnbr = %s
          AND (l.IMS_DEL_FLG IS NULL OR l.IMS_DEL_FLG <> 'V')
    """
    print(f"Running SQL for IDNBR {idnbr}...")
    with connection.cursor() as cur:
        cur.execute(sql, (idnbr,))
        rows = cur.fetchall()
        print(f"Found {len(rows)} matching service lines:")
        for r in rows:
            print(f"  SKU: {r[12]}, ID: {r[0]}, Desc: {r[2]}")

if __name__ == "__main__":
    test_sql(43771)
