/* Kirole site — progressive enhancement only.
   Without this file the page is fully readable and static. */
(() => {
  "use strict";

  const root = document.documentElement;
  root.classList.remove("no-js");
  root.classList.add("js");

  const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const supportsSDA =
    typeof CSS !== "undefined" &&
    CSS.supports("animation-timeline: view()");

  root.classList.add(supportsSDA ? "sda" : "io");

  /* --- Reveal fallback for browsers without scroll-driven animations --- */
  if (!supportsSDA) {
    const targets = document.querySelectorAll("[data-reveal]");
    if (reduceMotion || !("IntersectionObserver" in window)) {
      targets.forEach((el) => el.classList.add("in"));
    } else {
      const io = new IntersectionObserver(
        (entries) => {
          for (const entry of entries) {
            if (entry.isIntersecting) {
              entry.target.classList.add("in");
              io.unobserve(entry.target);
            }
          }
        },
        { threshold: 0.16 }
      );
      targets.forEach((el) => io.observe(el));
    }
  }

  /* --- Marquee: duplicate content once for a seamless loop --- */
  const track = document.querySelector(".marquee-track");
  if (track) {
    const clones = [...track.children].map((node) => {
      const clone = node.cloneNode(true);
      clone.setAttribute("aria-hidden", "true");
      return clone;
    });
    track.append(...clones);
  }

  /* --- E-ink refresh pulse helper --- */
  const pulse = (screen) => {
    if (reduceMotion || !screen) return;
    screen.classList.remove("flash");
    void screen.offsetWidth; /* restart the animation */
    screen.classList.add("flash");
  };

  document.querySelectorAll(".screen").forEach((screen) => {
    screen.addEventListener("animationend", (e) => {
      if (e.animationName === "eink-flash") screen.classList.remove("flash");
    });
  });

  /* --- Hero device: one boot refresh after load --- */
  const heroScreen = document.querySelector(".hero .screen");
  if (heroScreen) setTimeout(() => pulse(heroScreen), 420);

  /* --- Story device: scene follows the step being read --- */
  const device = document.querySelector("[data-story-device]");
  if (device) {
    const screen = device.querySelector(".screen");
    const scenes = device.querySelectorAll(".scene");
    const steps = document.querySelectorAll(".step[data-scene]");
    let current = "morning";

    const show = (name) => {
      if (name === current) return;
      current = name;
      scenes.forEach((s) => s.toggleAttribute("hidden", s.dataset.scene !== name));
      pulse(screen);
    };

    if ("IntersectionObserver" in window) {
      const watcher = new IntersectionObserver(
        (entries) => {
          for (const entry of entries) {
            if (entry.isIntersecting) show(entry.target.dataset.scene);
          }
        },
        { rootMargin: "-45% 0px -45% 0px" }
      );
      steps.forEach((step) => watcher.observe(step));
    }
  }
})();
