export type ThemePreference = 'system' | 'light' | 'dark'

const STORAGE_KEY = 'nmy:theme'

/** Read the user's saved theme preference, defaulting to "system". */
export function loadTheme(): ThemePreference {
  try {
    const v = localStorage.getItem(STORAGE_KEY)
    if (v === 'light' || v === 'dark' || v === 'system') return v
  } catch {
    /* localStorage unavailable (private mode, file://) */
  }
  return 'system'
}

/** Apply the preference to the document root and persist it. */
export function applyTheme(pref: ThemePreference): void {
  const root = document.documentElement
  if (pref === 'system') {
    delete root.dataset.theme
  } else {
    root.dataset.theme = pref
  }
  try {
    localStorage.setItem(STORAGE_KEY, pref)
  } catch {
    /* ignore */
  }
}

export function cycleTheme(current: ThemePreference): ThemePreference {
  return current === 'system' ? 'light' : current === 'light' ? 'dark' : 'system'
}
