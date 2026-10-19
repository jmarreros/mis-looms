use std::cell::{Cell, RefCell};
use std::f64::consts::PI;
use std::io::{Read, Write};
use std::rc::Rc;
use std::time::{Duration, Instant};

use gtk::prelude::*;
use gtk::{gdk, glib};
use gtk4 as gtk;
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};
use tokio::sync::mpsc;

use crate::{Cmd, Snapshot, Status, UiEvent, api, config};

const CSS: &str = r#"
window.mis-looms-capa { background: transparent; }
.pildora {
  background: #1c1a17; color: #f3ece4; border-radius: 999px; padding: 6px;
  border: 1px solid rgba(243, 236, 228, 0.10);
  font-family: Figtree, "Noto Sans", sans-serif; font-size: 14px;
}
.pildora button {
  border-radius: 999px; min-height: 32px; min-width: 32px; padding: 0 10px;
  background: rgba(243, 236, 228, 0.07); color: #f3ece4; border: none; box-shadow: none;
}
.pildora button:hover { background: rgba(243, 236, 228, 0.14); }
.pildora button.principal { background: #d67f48; color: #1c1a17; font-weight: 700; }
.pildora button.principal:hover { background: #e08d58; }
.pildora button.peligro { background: rgba(239, 83, 80, 0.18); color: #ff8a80; }
.pildora .asa { color: rgba(243, 236, 228, 0.35); padding: 0 2px 0 6px; }
.pildora .reloj { font-weight: 700; color: #ef5350; padding: 0 6px; font-feature-settings: "tnum"; }
.pildora .reloj.pausa { color: #f2c14e; }
.pildora .texto { padding: 0 8px; }
.pildora .tenue { color: rgba(243, 236, 228, 0.6); padding: 0 8px; }
.cuenta { font-family: Caprasimo, Figtree, sans-serif; font-size: 96px; color: #f3ece4; }
window.ajustes { background: #1c1a17; color: #f3ece4; font-family: Figtree, "Noto Sans", sans-serif; }
window.ajustes .titulo { font-family: Caprasimo, Figtree, sans-serif; font-size: 22px; }
window.ajustes .ayuda { color: rgba(243, 236, 228, 0.6); font-size: 12px; }
window.ajustes entry, window.ajustes passwordentry {
  border-radius: 999px; min-height: 38px; padding: 0 14px;
  background: #2a2723; color: #f3ece4; border: 1px solid rgba(243, 236, 228, 0.12); box-shadow: none;
}
window.ajustes entry:focus-within, window.ajustes passwordentry:focus-within {
  border-color: #d67f48; outline: none;
}
window.ajustes button {
  border-radius: 999px; min-height: 38px; padding: 0 18px;
  background: rgba(243, 236, 228, 0.08); color: #f3ece4; border: none; box-shadow: none;
}
window.ajustes button.principal { background: #d67f48; color: #1c1a17; font-weight: 700; }
window.ajustes .ok { color: #9cc69b; }
window.ajustes .error { color: #ff8a80; }
"#;

/// Bucle de GTK en el hilo principal. Recibe instantáneas del controlador y le manda comandos.
pub fn run(tx: mpsc::UnboundedSender<Cmd>, events: async_channel::Receiver<UiEvent>, rt: tokio::runtime::Handle) {
    glib::set_prgname(Some("mis-looms"));
    if let Err(e) = gtk::init() {
        eprintln!("sin interfaz gráfica ({e}); solo bandeja y D-Bus");
        // Sin GTK el controlador sigue funcionando: esperamos a que pida salir.
        while let Ok(ev) = events.recv_blocking() {
            if matches!(ev, UiEvent::Quit) {
                break;
            }
        }
        return;
    }
    let provider = gtk::CssProvider::new();
    provider.load_from_string(CSS);
    gtk::style_context_add_provider_for_display(
        &gdk::Display::default().expect("display"),
        &provider,
        gtk::STYLE_PROVIDER_PRIORITY_APPLICATION,
    );
    hyprland_rules();

    let ui = Rc::new(Ui {
        tx: tx.clone(),
        rt,
        panel: Panel::new(tx.clone()),
        countdown: Countdown::new(),
        settings: RefCell::default(),
        snapshot: RefCell::default(),
    });
    let main_loop = glib::MainLoop::new(None, false);
    {
        let (ui, main_loop) = (ui.clone(), main_loop.clone());
        glib::spawn_future_local(async move {
            while let Ok(ev) = events.recv().await {
                match ev {
                    UiEvent::Snapshot(s) => ui.update(s),
                    UiEvent::OpenSettings => ui.open_settings(),
                    UiEvent::Quit => break,
                }
            }
            main_loop.quit();
        });
    }
    main_loop.run();
}

/// En Hyprland: sin animación para la píldora y la cuenta regresiva, y que la ventana
/// de Ajustes flote. Se aplica en caliente; si no es Hyprland, no pasa nada.
fn hyprland_rules() {
    if std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_none() {
        return;
    }
    for rule in [
        r#"hl.layer_rule({ match = { namespace = "^mis-looms" }, no_anim = true })"#,
        r#"hl.window_rule({ match = { class = "^mis-looms$" }, float = true, center = true })"#,
    ] {
        let _ = std::process::Command::new("hyprctl")
            .args(["eval", rule])
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn();
    }
}

struct Ui {
    tx: mpsc::UnboundedSender<Cmd>,
    rt: tokio::runtime::Handle,
    panel: Rc<Panel>,
    countdown: Countdown,
    settings: RefCell<Option<gtk::Window>>,
    snapshot: RefCell<Option<Snapshot>>,
}

impl Ui {
    fn update(&self, s: Snapshot) {
        self.panel.update(&s);
        match s.status {
            Status::Countdown(n) => self.countdown.show(n),
            _ => self.countdown.hide(),
        }
        *self.snapshot.borrow_mut() = Some(s);
    }

    fn open_settings(&self) {
        if let Some(w) = self.settings.borrow().as_ref() {
            w.present();
            return;
        }
        let url = self.snapshot.borrow().as_ref().and_then(|s| s.config.server_url.clone()).unwrap_or_default();
        let window = settings_window(&url, self.tx.clone(), self.rt.clone());
        window.present();
        *self.settings.borrow_mut() = Some(window);
    }
}

fn layer_window(namespace: &str) -> gtk::Window {
    let window = gtk::Window::new();
    window.add_css_class("mis-looms-capa");
    window.init_layer_shell();
    window.set_layer(Layer::Overlay);
    window.set_keyboard_mode(KeyboardMode::None);
    window.set_namespace(Some(namespace));
    window.set_decorated(false);
    window
}

fn format_time(d: Duration) -> String {
    let s = d.as_secs();
    if s >= 3600 { format!("{}:{:02}:{:02}", s / 3600, s / 60 % 60, s % 60) } else { format!("{:02}:{:02}", s / 60, s % 60) }
}

// MARK: - Píldora de controles flotantes

struct Panel {
    window: gtk::Window,
    content: gtk::Box,
    tx: mpsc::UnboundedSender<Cmd>,
    /// Lo que define qué botones se muestran; si no cambia, no se reconstruye.
    shown: Cell<Option<(Status, Option<u8>)>>,
    clock: RefCell<Option<gtk::Label>>,
    snapshot: RefCell<Option<Snapshot>>,
    position: Cell<(i32, i32)>,
    confirm_discard: Cell<bool>,
}

impl Panel {
    fn new(tx: mpsc::UnboundedSender<Cmd>) -> Rc<Self> {
        let window = layer_window("mis-looms");
        window.set_anchor(Edge::Left, true);
        window.set_anchor(Edge::Bottom, true);
        let content = gtk::Box::new(gtk::Orientation::Horizontal, 6);
        content.add_css_class("pildora");
        window.set_child(Some(&content));

        let panel = Rc::new(Self {
            window,
            content,
            tx,
            shown: Cell::new(None),
            clock: RefCell::default(),
            snapshot: RefCell::default(),
            position: Cell::new((24, 24)),
            confirm_discard: Cell::new(false),
        });
        panel.setup_drag();

        let weak = Rc::downgrade(&panel);
        glib::timeout_add_local(Duration::from_millis(250), move || {
            let Some(panel) = weak.upgrade() else { return glib::ControlFlow::Break };
            if let (Some(label), Some(s)) = (panel.clock.borrow().as_ref(), panel.snapshot.borrow().as_ref()) {
                label.set_label(&format_time(s.elapsed()));
            }
            glib::ControlFlow::Continue
        });
        panel
    }

    fn send(&self, cmd: Cmd) {
        let _ = self.tx.send(cmd);
    }

    fn set_position(&self, (x, y): (i32, i32)) {
        self.position.set((x, y));
        self.window.set_margin(Edge::Left, x);
        self.window.set_margin(Edge::Bottom, y);
    }

    fn update(self: &Rc<Self>, s: &Snapshot) {
        if self.snapshot.borrow().is_none() {
            self.set_position(s.config.panel_position);
        }
        *self.snapshot.borrow_mut() = Some(s.clone());
        self.window.set_visible(s.config.show_panel);
        let key = (s.status, if s.status == Status::Idle { s.upload } else { None });
        if self.shown.get() != Some(key) {
            self.shown.set(Some(key));
            self.rebuild(s);
        }
    }

    fn button(self: &Rc<Self>, icon: Option<&str>, label: Option<&str>, tip: &str, class: Option<&str>, on: impl Fn(&Rc<Self>) + 'static) -> gtk::Button {
        let b = gtk::Button::new();
        match (icon, label) {
            (Some(icon), Some(label)) => {
                let row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
                row.append(&gtk::Image::from_icon_name(icon));
                row.append(&gtk::Label::new(Some(label)));
                b.set_child(Some(&row));
            }
            (Some(icon), None) => b.set_icon_name(icon),
            (None, label) => b.set_label(label.unwrap_or_default()),
        }
        b.set_tooltip_text(Some(tip));
        b.set_focusable(false);
        if let Some(c) = class {
            b.add_css_class(c);
        }
        let weak = Rc::downgrade(self);
        b.connect_clicked(move |_| {
            if let Some(p) = weak.upgrade() {
                on(&p)
            }
        });
        b
    }

    fn rebuild(self: &Rc<Self>, s: &Snapshot) {
        while let Some(child) = self.content.first_child() {
            self.content.remove(&child);
        }
        *self.clock.borrow_mut() = None;
        self.confirm_discard.set(false);

        let grip = gtk::Label::new(Some("⠿"));
        grip.add_css_class("asa");
        grip.set_tooltip_text(Some("Arrastra para mover"));
        self.content.append(&grip);

        let text = |t: &str, class: &str| {
            let l = gtk::Label::new(Some(t));
            l.add_css_class(class);
            l
        };
        match s.status {
            Status::Idle => {
                self.content.append(&self.button(Some("media-record-symbolic"), Some("Grabar"), "Iniciar grabación", Some("principal"), |p| p.send(Cmd::Start)));
                if let Some(pct) = s.upload {
                    self.content.append(&text(&format!("Subiendo {pct} %"), "tenue"));
                }
                self.content.append(&self.button(Some("window-close-symbolic"), None, "Salir de Mis Looms", None, |p| p.send(Cmd::Quit)));
            }
            Status::Starting => self.content.append(&text("Preparando…", "texto")),
            Status::Countdown(n) => {
                self.content.append(&text(&format!("Empieza en {n}"), "texto"));
                self.content.append(&self.button(Some("window-close-symbolic"), None, "Cancelar", None, |p| p.send(Cmd::CancelCountdown)));
            }
            Status::Recording | Status::Paused => {
                let paused = s.status == Status::Paused;
                let clock = text(&format_time(s.elapsed()), "reloj");
                if paused {
                    clock.add_css_class("pausa");
                }
                self.content.append(&clock);
                *self.clock.borrow_mut() = Some(clock);
                if paused {
                    self.content.append(&self.button(Some("media-playback-start-symbolic"), None, "Reanudar", None, |p| p.send(Cmd::TogglePause)));
                    let discard = self.button(Some("user-trash-symbolic"), None, "Descartar grabación", Some("peligro"), |_| {});
                    let weak = Rc::downgrade(self);
                    discard.connect_clicked(move |b| {
                        let Some(p) = weak.upgrade() else { return };
                        if p.confirm_discard.replace(true) {
                            p.send(Cmd::Discard);
                            return;
                        }
                        // Pide un segundo clic en 4 s antes de borrar.
                        b.set_label("¿Descartar? Pulsa de nuevo");
                        let (weak, b) = (Rc::downgrade(&p), b.clone());
                        glib::timeout_add_local_once(Duration::from_secs(4), move || {
                            if let Some(p) = weak.upgrade()
                                && p.confirm_discard.replace(false) && b.parent().is_some() {
                                    b.set_icon_name("user-trash-symbolic");
                                }
                        });
                    });
                    self.content.append(&discard);
                } else {
                    self.content.append(&self.button(Some("media-playback-pause-symbolic"), None, "Pausar", None, |p| p.send(Cmd::TogglePause)));
                }
                self.content.append(&self.button(Some("media-playback-stop-symbolic"), Some("Finalizar"), "Finalizar y subir", Some("principal"), |p| p.send(Cmd::Stop)));
            }
            Status::Stopping => self.content.append(&text("Finalizando…", "texto")),
        }
        // Las ventanas de GTK4 no encogen solas al quitar botones.
        self.window.set_default_size(1, 1);
    }

    /// Arrastre desde el asa o el cronómetro (los botones se quedan el clic). En Wayland una
    /// superficie no conoce su posición en pantalla, así que se usa el cursor global de
    /// Hyprland; en otro compositor la píldora salta a su sitio al soltar.
    fn setup_drag(self: &Rc<Self>) {
        let drag = gtk::GestureDrag::new();
        let start: Rc<Cell<((i32, i32), Option<(f64, f64)>)>> = Rc::new(Cell::new(((0, 0), None)));
        {
            let (weak, start) = (Rc::downgrade(self), start.clone());
            drag.connect_drag_begin(move |_, _, _| {
                if let Some(p) = weak.upgrade() {
                    start.set((p.position.get(), hyprland_cursor()));
                }
            });
        }
        let target = {
            let start = start.clone();
            move |p: &Panel, dx: f64, dy: f64| {
                let ((x0, y0), cursor0) = start.get();
                let (dx, dy) = match (cursor0, hyprland_cursor()) {
                    (Some((cx0, cy0)), Some((cx, cy))) => (cx - cx0, cy - cy0),
                    _ => (dx, dy),
                };
                let (w, h) = p.monitor_size();
                let (pw, ph) = (p.window.width(), p.window.height());
                ((x0 + dx as i32).clamp(0, (w - pw).max(0)), (y0 - dy as i32).clamp(0, (h - ph).max(0)))
            }
        };
        {
            let (weak, target, start) = (Rc::downgrade(self), target.clone(), start.clone());
            drag.connect_drag_update(move |_, dx, dy| {
                if let Some(p) = weak.upgrade()
                    && start.get().1.is_some() {
                        p.set_position(target(&p, dx, dy));
                    }
            });
        }
        {
            let weak = Rc::downgrade(self);
            drag.connect_drag_end(move |_, dx, dy| {
                if let Some(p) = weak.upgrade() {
                    let pos = target(&p, dx, dy);
                    p.set_position(pos);
                    p.send(Cmd::PanelPosition(pos.0, pos.1));
                }
            });
        }
        self.content.add_controller(drag);
    }

    fn monitor_size(&self) -> (i32, i32) {
        let display = WidgetExt::display(&self.window);
        let monitor = self
            .window
            .surface()
            .and_then(|s| display.monitor_at_surface(&s))
            .or_else(|| display.monitors().item(0).and_downcast::<gdk::Monitor>());
        monitor.map(|m| (m.geometry().width(), m.geometry().height())).unwrap_or((1920, 1080))
    }
}

/// Posición global del cursor (píxeles lógicos) por el socket de Hyprland.
fn hyprland_cursor() -> Option<(f64, f64)> {
    let sig = std::env::var("HYPRLAND_INSTANCE_SIGNATURE").ok()?;
    let dir = std::env::var("XDG_RUNTIME_DIR").ok()?;
    let mut sock = std::os::unix::net::UnixStream::connect(format!("{dir}/hypr/{sig}/.socket.sock")).ok()?;
    sock.set_read_timeout(Some(Duration::from_millis(100))).ok()?;
    sock.write_all(b"j/cursorpos").ok()?;
    let mut out = String::new();
    sock.read_to_string(&mut out).ok()?;
    let v: serde_json::Value = serde_json::from_str(&out).ok()?;
    Some((v["x"].as_f64()?, v["y"].as_f64()?))
}

// MARK: - Cuenta regresiva

/// 3, 2, 1 grande en el centro de la pantalla, con un anillo que se vacía cada segundo.
struct Countdown {
    window: gtk::Window,
    label: gtk::Label,
    current: Rc<Cell<Option<(u32, Instant)>>>,
}

impl Countdown {
    fn new() -> Self {
        let window = layer_window("mis-looms-cuenta");
        window.set_default_size(200, 200);
        window.set_can_target(false);
        let current: Rc<Cell<Option<(u32, Instant)>>> = Rc::default();

        let area = gtk::DrawingArea::new();
        area.set_content_width(200);
        area.set_content_height(200);
        {
            let current = current.clone();
            area.set_draw_func(move |_, cr, w, h| {
                let (cx, cy, r) = (w as f64 / 2.0, h as f64 / 2.0, w.min(h) as f64 / 2.0 - 6.0);
                cr.set_source_rgba(0.11, 0.10, 0.09, 0.88);
                cr.arc(cx, cy, r, 0.0, 2.0 * PI);
                let _ = cr.fill();
                cr.set_line_width(6.0);
                cr.set_source_rgba(0.95, 0.92, 0.89, 0.12);
                cr.arc(cx, cy, r - 8.0, 0.0, 2.0 * PI);
                let _ = cr.stroke();
                let left = current.get().map_or(1.0, |(_, t)| 1.0 - t.elapsed().as_secs_f64().min(1.0));
                cr.set_source_rgb(0.84, 0.50, 0.28); // #d67f48
                cr.arc(cx, cy, r - 8.0, -PI / 2.0, -PI / 2.0 + 2.0 * PI * left);
                let _ = cr.stroke();
            });
        }
        area.add_tick_callback(|area, _| {
            area.queue_draw();
            glib::ControlFlow::Continue
        });

        let label = gtk::Label::new(None);
        label.add_css_class("cuenta");
        let overlay = gtk::Overlay::new();
        overlay.set_child(Some(&area));
        overlay.add_overlay(&label);
        window.set_child(Some(&overlay));
        Self { window, label, current }
    }

    fn show(&self, n: u32) {
        if self.current.get().map(|c| c.0) != Some(n) {
            self.current.set(Some((n, Instant::now())));
            self.label.set_label(&n.to_string());
        }
        self.window.set_visible(true);
    }

    fn hide(&self) {
        self.current.set(None);
        self.window.set_visible(false);
    }
}

// MARK: - Ajustes

fn settings_window(url: &str, tx: mpsc::UnboundedSender<Cmd>, rt: tokio::runtime::Handle) -> gtk::Window {
    let window = gtk::Window::builder().title("Ajustes de Mis Looms").default_width(460).resizable(false).build();
    window.add_css_class("ajustes");
    window.set_hide_on_close(true);

    let col = gtk::Box::new(gtk::Orientation::Vertical, 10);
    col.set_margin_top(24);
    col.set_margin_bottom(24);
    col.set_margin_start(24);
    col.set_margin_end(24);

    let label = |t: &str, class: &str| {
        let l = gtk::Label::new(Some(t));
        l.set_xalign(0.0);
        l.set_wrap(true);
        l.add_css_class(class);
        l
    };
    col.append(&label("Mis Looms", "titulo"));
    col.append(&label("URL del servidor", "campo"));
    let url_entry = gtk::Entry::builder().text(url).placeholder_text("https://midominio.com/mis-looms").build();
    col.append(&url_entry);
    col.append(&label("Token de la app", "campo"));
    let token_entry = gtk::PasswordEntry::builder().show_peek_icon(true).placeholder_text("Pega el token del panel").build();
    token_entry.set_text(&config::api_token().unwrap_or_default());
    col.append(&token_entry);
    col.append(&label("Se genera en el panel web › Token de la app. Se guarda en el llavero del sistema.", "ayuda"));

    let status = label("", "ok");
    status.set_visible(false);
    col.append(&status);

    let buttons = gtk::Box::new(gtk::Orientation::Horizontal, 10);
    buttons.set_halign(gtk::Align::End);
    buttons.set_margin_top(6);
    let test = gtk::Button::with_label("Probar conexión");
    let save = gtk::Button::with_label("Guardar");
    save.add_css_class("principal");
    buttons.append(&test);
    buttons.append(&save);
    col.append(&buttons);
    window.set_child(Some(&col));

    let show = {
        let status = status.clone();
        move |ok: bool, text: &str| {
            status.set_label(text);
            status.set_css_classes(&[if ok { "ok" } else { "error" }]);
            status.set_visible(true);
        }
    };
    // Prueba la conexión en tokio y devuelve el resultado al hilo de GTK.
    let check = {
        let (url_entry, token_entry, rt) = (url_entry.clone(), token_entry.clone(), rt.clone());
        move || {
            let (url, token) = (url_entry.text().to_string(), token_entry.text().to_string());
            let rt = rt.clone();
            async move {
                let normalized = config::normalize_url(&url).ok_or_else(|| "La URL no es válida.".to_owned())?;
                rt.spawn(async move {
                    let client = api::Client::new(&normalized, &token).map_err(|e| e.to_string())?;
                    client.ping().await.map_err(|e| e.to_string())?;
                    Ok::<_, String>(normalized)
                })
                .await
                .map_err(|e| e.to_string())?
            }
        }
    };
    {
        let (show, check) = (show.clone(), check.clone());
        test.connect_clicked(move |b| {
            let (show, check, b) = (show.clone(), check.clone(), b.clone());
            b.set_sensitive(false);
            glib::spawn_future_local(async move {
                match check().await {
                    Ok(_) => show(true, "Conexión correcta."),
                    Err(e) => show(false, &e),
                }
                b.set_sensitive(true);
            });
        });
    }
    {
        let (window, token_entry) = (window.clone(), token_entry.clone());
        save.connect_clicked(move |b| {
            let (show, check, b, window, tx) = (show.clone(), check.clone(), b.clone(), window.clone(), tx.clone());
            let token = token_entry.text().to_string();
            b.set_sensitive(false);
            glib::spawn_future_local(async move {
                let result = async {
                    let url = check().await?;
                    config::save_api_token(token.trim()).map_err(|e| format!("{e:#}"))?;
                    let _ = tx.send(Cmd::ServerUrl(url));
                    Ok::<_, String>(())
                }
                .await;
                match result {
                    Ok(()) => {
                        show(true, "Guardado. Las grabaciones se subirán solas.");
                        glib::timeout_add_local_once(Duration::from_millis(1200), move || window.close());
                    }
                    Err(e) => show(false, &e),
                }
                b.set_sensitive(true);
            });
        });
    }
    window
}
