# Build 16 · empezar el entrenamiento correcto

19 de octubre de 2026. Continúa el Build 15 local. Datos, firma Personal Team,
identificadores, emparejamiento, icono y script privado de renovación conservados.

| Punto | Estado y evidencia |
| --- | --- |
| Distinguir el plan guardado de lo que indica el chat | Implementado. Hoy muestra «Entrenamiento guardado» y Cambiar entrenamiento; no sugiere haber leído el chat. |
| Captura/Pegar → revisión directa | Verificado nativamente con Vision local y captura genérica de Pierna; Pegar abre la misma revisión. |
| Mensajes con nombres y cantidades en líneas separadas | Pruebas de bloques numerados/Markdown, etiquetas, comas decimales y texto accesorio. Original disponible en revisión. |
| No inventar datos faltantes | Rangos y unidades/rest faltantes explícitos. Elegir descanso común no sobrescribe el indicado por el coach. |
| Peso elegido al registrar | Implementado y probado en Watch. Peso ausente no se presenta como objetivo cero; primer registro a cero requiere confirmación. |
| Cambiar Torso por Pierna | Aceptación explícita en iPhone y en Watch si hay una sesión anterior sin registros; trabajo registrado permanece intacto. |
| Preservar el plan anterior | Prueba de archivo en Rutinas sin crear historial ficticio ni duplicados al repetir guardado. |
| Registro → Historial → recuperación | Cinco series por toques nativos: 3 × (2 kg, 9 reps), 2 × (3 kg, 12 reps). Entrega única y mismas entradas tras relanzar ambas apps. |
| Compatibilidad, deshacer, informes, duplicados | 161 pruebas Swift / 21 suites y 13 Python aprobadas. Incluye esquema 3, datos antiguos, valores confirmados y rechazo de cargas contradictorias. |
| Diseño | Capturas reales de Hoy, importación, revisión, cambio, registro, descanso y resumen inspeccionadas en iPhone/Watch 46 mm. Texto accesible y acciones fijas comprobados; contenido secundario admite scroll. |
| Reduce Motion | Activado y leído en ambos simuladores; restaurado después. No acredita sensación física ni rendimiento de animación. |
| Compilación e instalación | Ambos SDK de simulador y productos firmados aprobados. Build 16 instalado y abierto en iPhone/Watch reales; versión leída de ambos. |
| Conservación de datos reales | Respaldos completos antes/después. Estado iPhone idéntico; Watch solo cambia fecha de sincronización. Cuatro archivos adicionales del iPhone y tres del Watch idénticos byte a byte, incluidos checkpoints/movimiento. |
| Limpieza | Archivos originales de ambos simuladores restaurados y comparados, ajustes restituidos, foto genérica retirada de la biblioteca. Emparejamiento conservado; últimas apps abiertas. |

## Límites concretos

- No se recibió la captura exacta que falló en el gimnasio. Se verificó una imagen
  genérica con el mismo tipo de mensaje, no todos los formatos/calidades de OCR.
- Little Lift no lee tu conversación privada ni adivina los ejercicios a partir
  de la palabra «pierna». Importar y aceptar sigue siendo una acción explícita.
- El peso no prescrito usa esquema 3; ambos dispositivos deben estar actualizados.
  Sin ID de variante y convención conocidos no hay comparación histórica exacta.
- Este pase no vuelve a verificar ChatGPT en vivo, doble toque físico, haptics,
  muñeca baja, batería ni precisión del experimento de movimiento. Los estados
  anteriores de esos puntos en la matriz F01–F27 siguen vigentes.

## Evidencia local

`BuildLogs/upgrade16-release-verification.log` y `upgrade16-final-signed.log`.
Respaldos, lectura de versiones, comparaciones y resultados nativos en
`.verification/upgrade-16/`; capturas `upgrade16-*` en `.verification/screenshots/`.
Son privados y no se publican con el código. Los tests reproducibles del motor
están en `GymStartTests.swift`; la guía de formatos está en `smart-import.md`.
