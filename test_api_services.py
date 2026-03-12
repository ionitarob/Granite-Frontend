
import os
import django
import sys
import json

backend_path = r'c:\Users\rmaglan\Documents\CTool Granite\Granite-Backend\django_backend'
sys.path.append(backend_path)
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'django_backend.settings')
django.setup()

from django.test import RequestFactory
from django.contrib.auth.models import User
from django.db import connection
from apps.orderops.views import order_services

def test_api_services(idnbr):
    sql = """
        SELECT DISTINCT
            c.id, c.family, c.description, c.extra_info_1, c.sku_config, c.sku_hp, c.sku_lenovo,
            c.coste, c.pvd, c.margen, c.collection_info,
            l.UNIT_PRICE,
            l.UNIT_COST,
            l.QTY_ORD
        FROM dbo.tbl_ConfigOrderLine l
        JOIN administracion.cotizaciones c ON (
            l.SKU = c.sku_config OR
            l.SKU = c.sku_hp OR
            l.SKU = c.sku_lenovo
        )
        WHERE l.parent_idnbr = %s
          AND (l.IMS_DEL_FLG IS NULL OR l.IMS_DEL_FLG <> 'V')
          AND (l.TIPO = 'P' OR l.TIPO IS NULL OR l.TIPO = '')
    """
    with connection.cursor() as cur:
        cur.execute(sql, [idnbr])
        rows = cur.fetchall()
        print(f"Found {len(rows)} rows for order {idnbr}")
        for r in rows:
            print(r)

if __name__ == "__main__":
    test_api_services(43771)
