import { createSignal } from 'solid-js'

// ─── Apply the correct class immediately (call this inline in <head>) ────────
export function applyTheme() {
  const stored = localStorage.getItem('theme')

  if (stored) {
    document.documentElement.setAttribute('data-theme', stored)
  } else {
    // System — remove the attribute and let the media query take over
    document.documentElement.removeAttribute('data-theme')
  }
}

export function useTheme() {
  const stored = localStorage.getItem('theme') ?? 'system'
  const [preference, setPreference] = createSignal(stored)

  const setTheme = (pref) => {
    setPreference(pref)
    if (pref === 'system') {
      localStorage.removeItem('theme')
    } else {
      localStorage.setItem('theme', pref)
    }
    applyTheme(pref)
  }

  return { preference, setTheme }
}
