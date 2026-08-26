(function () {
  "use strict";

  const header = document.querySelector(".header");
  const toggle = document.querySelector(".nav__toggle");
  const navLinks = document.querySelector(".nav__links");

  // Header scroll state
  function onScroll() {
    header.classList.toggle("header--scrolled", window.scrollY > 20);
  }
  window.addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  // Mobile menu
  if (toggle && navLinks) {
    toggle.addEventListener("click", () => {
      const open = toggle.classList.toggle("nav__toggle--open");
      navLinks.classList.toggle("nav__links--open", open);
      toggle.setAttribute("aria-expanded", String(open));
    });

    navLinks.querySelectorAll("a").forEach((link) => {
      link.addEventListener("click", () => {
        toggle.classList.remove("nav__toggle--open");
        navLinks.classList.remove("nav__links--open");
        toggle.setAttribute("aria-expanded", "false");
      });
    });
  }

  // Scroll reveal
  const reveals = document.querySelectorAll(".reveal");
  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("visible");
          observer.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.12, rootMargin: "0px 0px -40px 0px" }
  );
  reveals.forEach((el) => observer.observe(el));

  // Copy to clipboard
  document.querySelectorAll(".copy-btn").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const text = btn.dataset.copy;
      if (!text) return;

      try {
        await navigator.clipboard.writeText(text);
        const original = btn.textContent;
        btn.textContent = "Copied!";
        btn.classList.add("copied");
        setTimeout(() => {
          btn.textContent = original;
          btn.classList.remove("copied");
        }, 2000);
      } catch {
        btn.textContent = "Error";
        setTimeout(() => { btn.textContent = "Copy"; }, 2000);
      }
    });
  });
})();
