# Build 17 · mi chat del gym y revisión de controles

19 de octubre de 2026. Continúa Build 16 local; no sustituye el proyecto por otra copia.

## Implementado

- **Hoy / Ajustes → Mi chat del gym** prepara un mensaje con la prescripción guardada,
  registros recientes permitidos, preferencias de exportación y formato exacto de respuesta.
  Incluye una petición opcional, por ejemplo «hoy acordamos pierna».
- Copiar, abrir ChatGPT, traer una respuesta, revisar y aceptar son pasos explícitos.
  La pantalla distingue mensaje copiado, respuesta aceptada y datos nuevos. Nunca afirma
  haber enviado o leído una conversación. [Guía](gym-chat.md).
- Cada respuesta lleva el identificador del mensaje copiado. Se rechazan respuestas
  repetidas, de otra petición o anteriores a cambios en el contexto. La aceptación vuelve
  a validar el contexto; guardar precede al envío al Watch. El JSON antiguo sigue válido.
- La propuesta original del coach queda archivada aunque se edite antes de aceptarla.
  Los registros realizados y el plan anterior se conservan.

## Fallos y acciones corregidos

| Control / situación | Corrección |
| --- | --- |
| Pegar en Mi chat del gym | La hoja recibe el texto como un único elemento de presentación. La prueba nativa encontró una hoja vacía con el primer mecanismo; se corrigió y se repitió el recorrido. |
| Pegar texto inválido | El cambio del campo ya no borra el error recién producido. Aviso visible en la propia importación. |
| Añadir rutina | Guarda para después; no cambia Hoy ni una sesión activa. |
| Importar desde Empieza aquí | Hoja con cierre correcto, sin una pila de navegación anidada que impida salir. |
| Revisar propuesta desde la cola | Presentación modal coherente y avisos de aceptación/descarte en la propia hoja. |
| Reintentar Atajo | El estado de apertura se libera explícitamente; no depende de que otra actualización de pantalla haga avanzar un límite de tiempo. |
| Abrir Atajos | Muestra si se pudo abrir y explica que solo un resultado recibido confirma análisis. |
| Quitar objetivo de tiempo | Deshabilitado cuando no existe; confirmación visible después de quitarlo. |
| Actualizar replays | Muestra que la biblioteca local se actualizó. No afirma haber recibido datos pendientes. |
| Sincronización de Hoy | Expone el estado real de conexión/reintento mientras falta recibo. |
| Plan/propuesta que ya no existe | Error explícito en lugar de salir silenciosamente. |
| Ajustar ejercicio en Watch | Los fallos se muestran en la pantalla actual; elegir/omitir no cierra la hoja antes de guardar correctamente. |
| Iniciar movimiento sin activarlo | Explicación de activación en iPhone junto al botón deshabilitado. La captura sigue siendo experimental. |

## Comprobado en este pase

| Cobertura | Evidencia observada |
| --- | --- |
| Motor y scripts | 167 pruebas Swift en 22 suites y 13 pruebas Python; generación de proyecto/recursos y compilación de ambos SDK de simulador aprobadas. |
| Compatibilidad y límites | JSON anterior, estado sin handoff, guardado/recarga, petición acotada, JSON duplicado, claves extra, bloqueo del atajo de importación por las rutas antiguas, fecha fraccionaria y rechazo atómico. |
| Mensaje → respuesta | Copiar al portapapeles nativo; respuesta ficticia con recibo; vista previa sin alterar Hoy; editar 10 a 11 reps; aceptar; mismo plan guardado en Watch. Propuesta original de 10 reps archivada. |
| Mensajes inválidos | Duplicado y respuesta desactualizada rechazados con alertas visibles. JSON con claves repetidas rechazado desde Pegar; Hoy intacto. |
| Contexto tras entrenar | Estado «hay datos nuevos» y copia actualizada con ID de sesión y valores registrados; apertura de Safari desde Abrir ChatGPT y confirmación de apertura. No se envió nada a un chat. |
| Watch 46 mm | Inicio, + de peso/reps, Log, deshacer, +30 s, saltar, resumen, Listo, ajustes y finalizar antes por toques nativos. Dos series de 20,5 kg × 12, frente a objetivo de 20 kg × 11. |
| Entrega y recuperación | Sesión completa y otra terminada antes llegan separadamente; reenvío del mismo ID se confirma sin duplicar Historial. Descanso absoluto y entradas conservados tras relanzar Watch; dos sesiones conservadas tras relanzar ambos. |
| Rutinas / Ayuda | Añadir y guardar rutina ficticia conserva Hoy. Importar desde Ayuda, mostrar error y Cerrar vuelve a Ayuda. |
| Tiempo / movimiento | Aplicar 45 minutos y quitar el objetivo cambian el estado guardado y muestran confirmación. Actualizar grabaciones muestra su resultado sin iniciar captura. |
| Informes | Historial muestra prescripción y valores reales separados. Copiar devuelve el informe correcto; Compartir abre la hoja nativa, sin enviar a ningún destino. |
| Diseño y accesibilidad | Capturas reales de Hoy, chat, revisión, errores, Rutinas, Historial y Watch inspeccionadas. Texto accesible del iPhone y XXXL del Watch; controles principales de Watch visibles. Reduce Motion activado y leído en ambos, luego restituido. No es una medición de fluidez o sensación física. |
| Dispositivos reales | Build 17 compilado con la misma firma gratuita, instalado y abierto en iPhone y Watch. Respaldos completos antes/después; estado iPhone igual, Watch solo cambia fecha de sync; otros 4 archivos del iPhone y 3 del Watch idénticos. |

## Alcance de «revisar todos los botones»

Se revisaron los controladores y estados habilitados de todas las familias de pantallas
nativas; no se encontraron acciones vacías de producción salvo cierres/cancelaciones
intencionales. Las acciones vacías en `#Preview` son ejemplos de diseño, no la app.
La tabla anterior enumera los recorridos repetidos con interacción nativa en Build 17.
Lo siguiente tiene revisión de código y pruebas del motor, pero **no se acredita como
una nueva prueba física de cada botón**:

| Familia | Cobertura adicional y límite |
| --- | --- |
| Editor completo / OCR / archivos / historial importado | Validadores y pruebas actuales aprobados. Vision real, archivos e importación de captura comprobados en Build 16; no se repitieron todas las imágenes posibles. |
| Calendario / perfil / contexto / preferencias / meta semanal | Guardado, permisos de exportación, validadores y pruebas existentes revisados; no se modificó la configuración personal real. |
| Progreso / correcciones / copias de seguridad | Pruebas actuales de agregación, auditoría de valores, conflictos, recuperación y duplicados. Las pruebas nativas completas de exportar/restaurar/corregir están en Build 14. |
| Cardio / alternativas / rutina abreviada / esfuerzo optativo | Regresión del motor aprobada; preservación de originales, reversión, pausas y límites revisados. Flujos nativos detallados en Builds 11–16. |
| Atajos / permisos / notificaciones | Apertura y gestión de errores revisadas. Esta nueva prueba de ChatGPT en vivo quedó bloqueada: Apple devolvió NSURLErrorDomain 502 dos veces al firmar el atajo temporal. No se importó ni ejecutó ese atajo; el existente permanece intacto. La verificación genérica anterior de Build 15 no prueba el nuevo prompt. |
| Motion / ritmo / complicación / doble toque | Controladores revisados y compilados. Sin nueva prueba física de sensores, haptics, batería, muñeca baja ni gesto doble toque. |

## Límites

No existe sincronización silenciosa demostrada con el hilo privado del usuario.
Un recibo local correlaciona el mensaje; **no autentica a ChatGPT ni prueba entrega**.
El usuario elige su conversación y comparte explícitamente. La respuesta debe respetar
el contrato; ambigüedades se resuelven antes de aceptar. No se garantiza ausencia de bugs.

No se compró nada ni se publicó la app; no se cambió el equipo Personal Team ni el emparejamiento.
No hay backend, scraping, credenciales de modelo o llamadas de inferencia pagadas.

Evidencia privada: `BuildLogs/upgrade17-verification.log`, `upgrade17-signed.log`,
`.verification/upgrade-17/` y capturas `upgrade17-*`. Los originales de los simuladores
se restituyeron y compararon; los datos ficticios no se publican como historial personal.
