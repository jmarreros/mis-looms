// Reproductor con controles propios: reproducir/pausar, volumen, tiempo, barra de progreso,
// velocidad y pantalla completa, más «Ver de nuevo» en el centro cuando el video termina.
//
// Por qué controles propios: la pantalla completa nativa del <video> no deja dibujar nada
// encima, así que hay que ampliar el marco (video + capas). Con los controles nativos, Chrome
// sigue mostrando su botón de pantalla completa (deshabilitado) y no se puede usar para el
// marco, así que habría dos botones. Sin JS se quedan los controles nativos del navegador.
(function () {
    var VELOCIDADES = [1, 1.25, 1.5, 2];
    var ESPERA_OCULTAR = 2500;  // ms sin mover el ratón para ocultar los controles al reproducir

    function elementoPantallaCompleta() {
        return document.fullscreenElement || document.webkitFullscreenElement || null;
    }

    function reloj(segundos) {
        if (!isFinite(segundos) || segundos < 0) segundos = 0;
        var s = Math.floor(segundos);
        var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = s % 60;
        var mmss = (h ? String(m).padStart(2, '0') : m) + ':' + String(r).padStart(2, '0');
        return h ? h + ':' + mmss : mmss;
    }

    document.querySelectorAll('[data-reproductor]').forEach(function (marco) {
        var video = marco.querySelector('video');
        var controles = marco.querySelector('[data-controles]');
        var barra = marco.querySelector('[data-barra]');
        var botonReproducir = marco.querySelector('[data-reproducir]');
        var botonSilenciar = marco.querySelector('[data-silenciar]');
        var botonVelocidad = marco.querySelector('[data-velocidad]');
        var botonAmpliar = marco.querySelector('[data-pantalla-completa]');
        var actual = marco.querySelector('[data-actual]');
        var total = marco.querySelector('[data-total]');
        var arrastrando = false;
        var temporizador = null;

        video.controls = false;
        controles.hidden = false;
        marco.classList.add('con-controles');
        marco.tabIndex = 0;  // para los atajos de teclado

        // --- Reproducción ---

        function alternarReproduccion() {
            if (video.paused || video.ended) video.play(); else video.pause();
        }

        function pintarEstado() {
            var reproduciendo = !video.paused && !video.ended;
            botonReproducir.classList.toggle('activo', reproduciendo);
            botonReproducir.setAttribute('aria-label', reproduciendo ? 'Pausar' : 'Reproducir');
            botonReproducir.title = (reproduciendo ? 'Pausar' : 'Reproducir') + ' (espacio)';
            marco.classList.toggle('sin-empezar', video.paused && !video.ended && video.currentTime === 0);
            marco.classList.toggle('terminado', video.ended);
            mostrarControles();
        }

        ['play', 'pause', 'ended', 'loadedmetadata'].forEach(function (evento) {
            video.addEventListener(evento, pintarEstado);
        });
        video.addEventListener('seeking', function () { marco.classList.remove('terminado', 'sin-empezar'); });
        video.addEventListener('click', alternarReproduccion);
        botonReproducir.addEventListener('click', alternarReproduccion);
        marco.querySelector('[data-iniciar]').addEventListener('click', function () { video.play(); });
        marco.querySelector('[data-repetir]').addEventListener('click', function () {
            video.currentTime = 0;
            video.play();
        });

        // --- Tiempo y barra de progreso ---

        function pintarTiempo() {
            var duracion = video.duration;
            var fraccion = isFinite(duracion) && duracion > 0 ? video.currentTime / duracion : 0;
            if (!arrastrando) barra.value = Math.round(fraccion * 1000);
            barra.style.setProperty('--progreso', (barra.value / 10) + '%');
            actual.textContent = reloj(video.currentTime);
            total.textContent = reloj(duracion);
        }

        ['timeupdate', 'durationchange', 'loadedmetadata', 'seeked'].forEach(function (evento) {
            video.addEventListener(evento, pintarTiempo);
        });
        barra.addEventListener('input', function () {
            arrastrando = true;
            if (isFinite(video.duration)) video.currentTime = barra.value / 1000 * video.duration;
            pintarTiempo();
        });
        barra.addEventListener('change', function () { arrastrando = false; });

        // --- Volumen y velocidad ---

        function pintarVolumen() {
            var mudo = video.muted || video.volume === 0;
            botonSilenciar.classList.toggle('activo', mudo);
            botonSilenciar.setAttribute('aria-label', mudo ? 'Activar sonido' : 'Silenciar');
            botonSilenciar.title = (mudo ? 'Activar sonido' : 'Silenciar') + ' (m)';
        }

        video.addEventListener('volumechange', pintarVolumen);
        botonSilenciar.addEventListener('click', function () { video.muted = !video.muted; });

        botonVelocidad.addEventListener('click', function () {
            var siguiente = VELOCIDADES[(VELOCIDADES.indexOf(video.playbackRate) + 1) % VELOCIDADES.length];
            video.playbackRate = siguiente;
            botonVelocidad.textContent = String(siguiente).replace('.', ',') + '×';
        });

        // --- Pantalla completa ---

        var puedeAmpliarMarco = !!(marco.requestFullscreen || marco.webkitRequestFullscreen);

        function alternarPantallaCompleta() {
            if (elementoPantallaCompleta() === marco) {
                (document.exitFullscreen || document.webkitExitFullscreen).call(document);
            } else if (puedeAmpliarMarco) {
                var pedir = marco.requestFullscreen || marco.webkitRequestFullscreen;
                Promise.resolve(pedir.call(marco)).catch(function () {});
            } else if (video.webkitEnterFullscreen) {
                video.webkitEnterFullscreen();  // iPhone: solo existe la del propio video
            }
        }

        function pintarPantallaCompleta() {
            var dentro = elementoPantallaCompleta() === marco;
            botonAmpliar.classList.toggle('activo', dentro);
            botonAmpliar.setAttribute('aria-label', dentro ? 'Salir de pantalla completa' : 'Pantalla completa');
            botonAmpliar.title = (dentro ? 'Salir de pantalla completa' : 'Pantalla completa') + ' (f)';
        }

        botonAmpliar.addEventListener('click', alternarPantallaCompleta);
        video.addEventListener('dblclick', alternarPantallaCompleta);
        document.addEventListener('fullscreenchange', pintarPantallaCompleta);
        document.addEventListener('webkitfullscreenchange', pintarPantallaCompleta);

        // --- Mostrar/ocultar controles: se ocultan al reproducir si el ratón no se mueve ---

        function mostrarControles() {
            marco.classList.remove('inactivo');
            clearTimeout(temporizador);
            if (!video.paused && !video.ended) {
                temporizador = setTimeout(function () {
                    if (!marco.contains(document.activeElement) || document.activeElement === marco) {
                        marco.classList.add('inactivo');
                    }
                }, ESPERA_OCULTAR);
            }
        }

        marco.addEventListener('mousemove', mostrarControles);
        marco.addEventListener('focusin', mostrarControles);
        marco.addEventListener('mouseleave', function () {
            if (!video.paused) marco.classList.add('inactivo');
        });

        // --- Teclado (con el foco en el reproductor) ---

        marco.addEventListener('keydown', function (evento) {
            if (evento.metaKey || evento.ctrlKey || evento.altKey) return;
            var enBarra = evento.target === barra;
            switch (evento.key) {
                case ' ':
                case 'k':
                    if (evento.target.tagName === 'BUTTON' && evento.key === ' ') return;  // el botón ya actúa
                    alternarReproduccion();
                    break;
                case 'f': alternarPantallaCompleta(); break;
                case 'm': video.muted = !video.muted; break;
                case 'ArrowLeft':
                    if (enBarra) return;
                    video.currentTime = Math.max(0, video.currentTime - 5);
                    break;
                case 'ArrowRight':
                    if (enBarra) return;
                    video.currentTime = Math.min(video.duration || 0, video.currentTime + 5);
                    break;
                default: return;
            }
            evento.preventDefault();
            mostrarControles();
        });

        pintarEstado();
        pintarTiempo();
        pintarVolumen();
        pintarPantallaCompleta();
    });
})();
