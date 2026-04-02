import { useTheme } from './theme'

export function ThemeToggle() {
  const { preference, setTheme } = useTheme()

  return (
    <div >
      <button classList={{ active: preference() === 'light' }} onClick={() => setTheme('light')}>Light</button>
      <button classList={{ active: preference() === 'system' }} onClick={() => setTheme('system')}>System</button>
      <button classList={{ active: preference() === 'dark' }} onClick={() => setTheme('dark')}>Dark</button>
    </div>
  )
}
