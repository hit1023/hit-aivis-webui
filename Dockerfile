FROM nginx:alpine
COPY index.html /usr/share/nginx/html/index.html
COPY docs/ /usr/share/nginx/html/docs/
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh
CMD ["/docker-entrypoint.sh"]
