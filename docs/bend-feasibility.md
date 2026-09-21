# Bend 2: ограничения для voxel-движка

Проверено 2026-09-21. Локально установлен **Bend 2.0.16**; upstream исследован на commit `a49524265bdfa5753a4bf38e25f0574a705dd868`. Совместимость всей демосцены с локальной версией пока не проверена. Числа из upstream shader guide — измерения авторов на других машинах, не бюджет нашего движка. Документы EFFECTS/SHADERS сами предупреждают, что написаны AI и ожидают человеческой проверки; API дополнительно сверен с Base/исходниками.

## Что подтверждено

- Есть `App.run`, `Window.open/frame/close`, `Image = Pix | Qua`; `Window.frame` возвращает окно, изображение и события. Ввод: `Key`, `Mouse`, `Move`, `Close`. Это готовый цикл приложения и вывод изображения, но не API аппаратного triangle rasterizer. Для своего fixed-step цикла и повторного использования изображения можно работать через `Window` напрямую. [Base](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/bend2/base.bend#L352).
- На Linux окно реализовано через X11, кадр разворачивается из `Image` и выводится через `XPutImage`. В Base нет публичной операции relative mouse / pointer lock; `Move` содержит абсолютные координаты. Для первой версии подходят orbit/drag-камера или ограниченное управление; полноценный FPS mouse-look требует отдельного platform effect. [Window.frame](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/bend2/effs/window_frame.c#L184), [Window.open](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/bend2/effs/window_open.c#L179).
- Native GPU: Metal на Apple, CUDA на Linux/NVIDIA. Vulkan не предусмотрен, Windows предлагается использовать через WSL. JavaScript выполняет вычисления последовательно. Без GPU вызов `!` может работать на CPU, поэтому сам факт успешного запуска ничего не доказывает о GPU. [Guide](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/guide/GUIDE.md#L156), [WONTFIX](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/WONTFIX.txt#L53).
- `Array<T>` даёт изменение на месте при единственном владельце. Чтение возвращает массив вместе с элементом, размер — степень двойки; индексы **циклически оборачиваются**, поэтому проверка координат перед индексированием обязательна. Нельзя пометить весь изменяемый мир `+` и раздать его всем задачам как обычные разделяемые данные. [Guide / Arrays](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/guide/GUIDE.md#L169).
- В pinned upstream уже есть `@unsafe Array.fork/join` и атомарные операции. В **локальном 2.0.16 `bend base Array.fork` отвечает, что такого имени нет**. Не использовать эти новые операции как основание первого дизайна; они также снимают часть гарантий единственного владельца. [Base / unsafe arrays](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/bend2/base.bend#L2280).
- Host effects исполняются event loop, а не GPU. Добавление C/JS effects предусмотрено, но C API зависит от версии компилятора, стабильный ABI не обещан; собственный opaque handle пока ограничен Base-типами. Это путь для будущего platform backend, но не бесплатный FFI к любому движку. [Effects](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/guide/EFFECTS.md), [ограничение handle](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/WONTFIX.txt#L47).
- Файловое сохранение реализуемо: `File.read_bytes/write_bytes/read_at/size` есть и локально. API использует `U32` для размера/offset и список слов для байтов, поэтому версия формата, упаковка и разбиение больших миров на файлы — задачи движка; нельзя молча считать этот API произвольным 64-битным файловым хранилищем. [Base / File](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/bend2/base.bend#L257).

## Следствия для архитектуры — проектные выводы

Хранить изменяемые чанки с явным владельцем; публиковать для рендера отдельные неизменяемые пакеты/меши. Делить обновление по независимым чанкам, исключив одновременную запись в соседние чанки; пограничные данные передавать отдельным снимком. Не полагаться на дешёвое клонирование всего мира.

Первый renderer целесообразно строить из поверхностей вокселей через существующий `bend3d`, затем измерять альтернативы. Это не доказательство превосходства мешей. Upstream shader guide специально рекомендует готовить кандидатов на CPU для экранных тайлов и предупреждает о стоимости per-ray обходов общего дерева, diverging work и reference counts. На CUDA есть дополнительная стоимость миграции managed-memory страниц через PCIe: результаты M4 не переносятся на GTX 1660. [Shader guide](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/guide/SHADERS.md).

Проверять CPU и GPU как отдельные режимы. Не обещать размер мира/FPS по демо; измерить время dirty-chunk updates, построения пакетов, raster, present и пик памяти. Для packed voxel слова считать размер runtime отдельно от числа бит материала: представление Bend-терма не равно автоматически плотно упакованному C `uint32_t`. [Runtime model](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/guide/GUIDE.md#L582).

## Локальная проверка CUDA

Временная программа `/tmp/bend-voxel-gpu-probe.bend` вычисляет `pow2!(16n)` рекурсивными параллельными вызовами и печатает результат через `IO.print`.

- Обычная сборка `bend ... -o /tmp/bend-voxel-gpu-probe` вывела `65536`, но файл `.gpu` не появился. Принудительный `--gpu on` завершился кодом 1: `bend: --gpu on, but this binary found no GPU device`.
- На машине отсутствует `/usr/local/cuda`; установленный toolkit находится в `/opt/cuda`. Компилятор умеет использовать `CUDA_HOME`. [Выбор CUDA в compiler](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/bend2/main.ts).
- Сборка с переменной **только для этой команды** `CUDA_HOME=/opt/cuda bend /tmp/bend-voxel-gpu-probe.bend -o /tmp/bend-voxel-gpu-probe-cuda` создала `.gpu` размером 34296 байт.
- `/tmp/bend-voxel-gpu-probe-cuda --gpu on` успешно вывела `65536` (код 0); бинарник связан с `libcuda.so.1` и `libnvrtc.so.13`.

Таким образом минимальный native CUDA путь на текущей машине работает. Это smoke-test установки и backend, **не тест voxel-сцены или FPS**. Bend/toolkit не обновлялись, системные настройки не менялись.
