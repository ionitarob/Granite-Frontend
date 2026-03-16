import sys

path = '/Volumes/Users/rmaglan/Documents/CTool Granite/Granite-Backend/django_backend/apps/serials/views.py'
with open(path, 'rb') as f:
    content = f.read()

search_pattern = b"return Response({'error': 'order not found'}"

if search_pattern in content:
    start_idx = content.find(search_pattern)
    end_pattern = b"try:"
    end_idx = content.find(end_pattern, start_idx)
    
    if end_idx != -1:
        new_block = b"            return Response({'error': 'order not found'}, status=status.HTTP_404_NOT_FOUND)
        if not order_row and do_save:
            "
        updated_content = content[:start_idx] + new_block + content[end_idx:]
        with open(path, 'wb') as f:
            f.write(updated_content)
        print('Successfully patched backend 404 logic.')
    else:
        print('Could not find try: block after return.')
else:
    print('Could not find target return statement.')
