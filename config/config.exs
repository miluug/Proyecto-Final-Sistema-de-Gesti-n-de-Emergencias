import Config

# Carpeta donde se guardan los archivos de texto plano (persistencia).
# Las pruebas usan otra carpeta para no dañar los datos reales.
if config_env() == :test do
  config :emergencias, directorio_datos: "datos_test"
else
  config :emergencias, directorio_datos: "datos"
end
