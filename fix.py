import sys
p='/Volumes/Users/rmaglan/Documents/CTool Granite/Granite-Backend/django_backend/apps/serials/views.py'
with open(p,'rb') as f: c=f.read()
m=b'status.HTTP_404_NOT_FOUND'
if m in c:
 i=c.find(m); rs=c.rfind(b'return',0,i); lm=b'if not order_row and do_save:'; li=c.find(lm,i)
 if rs!=-1 and li!=-1:
  e=li+len(lm); nb=b'            return Response({\'error\': \'order not found\'}, status=status.HTTP_404_NOT_FOUND)
        if not order_row and do_save:'; nc=c[:rs]+nb+c[e:]
  with open(p,'wb') as f: f.write(nc)
  print('OK')
