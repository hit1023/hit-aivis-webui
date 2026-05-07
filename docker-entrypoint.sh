#!/bin/sh
sed -i "s|__AIVIS_API_URL__|${AIVIS_API_URL}|g" /usr/share/nginx/html/index.html
exec nginx -g "daemon off;"
