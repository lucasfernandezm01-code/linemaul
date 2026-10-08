# Line & Maul

Fantasy ("Mi XV") y Prode de rugby argentino. Dueño: Lucas (habla en español rioplatense, prefiere respuestas cortas).

- `index.html`: todo el sitio (HTML + CSS + JS en un archivo). Se publica solo con GitHub Pages (`.github/workflows/pages.yml`) al hacer push a `main`.
- Base y login: Supabase (`https://srdnktmbipvpvyzguuyk.supabase.co`, publishable key en `index.html`). Esquema en `supabase/` (se corre a mano en el SQL Editor; desde el entorno de Claude no hay acceso de red a Supabase).
- La capa `makeDb()` imita la API vieja (doc/collection/onSnapshot) sobre las tablas: config, fechas, profiles (nombre, equipo, club), equipos y prode (una fila por usuario y fecha; la base bloquea cambios fuera de la fecha abierta), ligas, liga_miembros, admins.
- Datos semanales: Claude arma un JSON y Lucas lo pega en Admin → Importar. Formato:
  `{"fechas": {"<id>": {campos que se mezclan en la fecha}}, "config": {"<key>": {campos}}, "borrar_fechas": ["<id>"], "reemplazar_config": false}`
- `datos/inicial.json`: planteles, camisetas y entrenadores 2026 (botón "Cargar datos iniciales").
- Probar sin red: servir la carpeta y reemplazar el script de supabase-js por un mock en memoria.
