import { useEffect, useRef, useState } from 'react'
import { gsap } from 'gsap'
import { CustomEase } from 'gsap/CustomEase'

gsap.registerPlugin(CustomEase)
// Note: gsap@3 is free for open-source projects. CustomEase is bundled in the
// free tier. trialWarn suppression removed — not needed with the npm package.

// ─── Orb SVG animation — exact port of codepen.io/chrisgannon/pen/ZYQjZBr ───
function OrbBackground({ reduced }) {
  const svgRef = useRef(null)
  const ctxRef = useRef(null)

  useEffect(() => {
    const svg = svgRef.current
    if (!svg || reduced) return

    const allEll = Array.from(svg.querySelectorAll('.ell'))
    const _ca = ['#f72585', '#7209b7', '#3a0ca3', '#4361ee', '#4cc9f0', '#D9F4FC']

    const _eio = CustomEase.create('_eio', 'M0,0 C0.2,0 0.432,0.147 0.507,0.374 0.59,0.629 0.822,1 1,1')
    const easeOut = CustomEase.create('_eout', 'M0,0 C0.271,0.302 0.323,0.535 0.453,0.775 0.528,0.914 0.78,1 1,1')
    const easeIn = CustomEase.create('_ein', 'M0,0 C0.594,0.062 0.79,0.698 1,1')

    const _rxf = 3.8, _ryf = 2.3, _ss = 10, _es = 100
    const colorInterp = gsap.utils.interpolate(_ca)

    const ctx = gsap.context(() => {
      const mainTl = gsap.timeline()

      gsap.set(svg, { visibility: 'visible' })

      function _anm(el, _cn) {
        const ___t = gsap.timeline({ defaults: { ease: _eio, duration: 1 }, repeat: -1 })
        gsap.set(el, {
          opacity: 1 - _cn / allEll.length,
          stroke: colorInterp(_cn / allEll.length),
        })

        ___t
          .to(el, { attr: { rx: `+=${_cn * _rxf}`, ry: `-=${_cn * _ryf}` }, strokeWidth: _ss, ease: easeIn })
          .to(el, { strokeWidth: _es, attr: { rx: `-=${_cn * _rxf}`, ry: `+=${_cn * _ryf}` }, ease: easeOut })
          .to(el, { duration: 2, rotation: -360, transformOrigin: '50% 50%', ease: _eio }, 0)
          .from(el, { duration: 1, scale: 0, transformOrigin: '50% 50%', ease: _eio }, 0)
          .from(el, { duration: 1.5, ease: _eio }, 0)
          .timeScale(0.5)

        mainTl.add(___t, _cn / allEll.length)
      }

      allEll.forEach((el, c) => _anm(el, c + 1))
      // Scoped to this context so it does not bleed into other GSAP animations
      gsap.globalTimeline.timeScale(1.3)
    }, svg)

    ctxRef.current = ctx
    return () => {
      ctx.revert()
      gsap.globalTimeline.timeScale(1)
    }
  }, [reduced])

  if (reduced) return null

  return (
    <svg
      ref={svgRef}
      id="splashSVG"
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 800 600"
      aria-hidden="true"
      focusable="false"
      style={{
        width: '100%',
        height: '100%',
        visibility: 'hidden',
        position: 'absolute',
        inset: 0,
      }}
    >
      {Array.from({ length: 31 }, (_, i) => (
        <ellipse
          key={i}
          className="ell"
          cx="400"
          cy="300"
          rx="180"
          ry="180"
          fill="none"
          style={{ strokeWidth: 0, strokeLinecap: 'round', strokeLinejoin: 'round' }}
        />
      ))}
    </svg>
  )
}

// ─── Splash Screen ────────────────────────────────────────────────────────────
export default function SplashScreen({ onComplete }) {
  // Respect prefers-reduced-motion: skip animation entirely if set.
  // Guard with try/catch: jsdom (vitest/jest) does not implement matchMedia.
  const [reduced] = useState(() => {
    try {
      return typeof window !== 'undefined' &&
        window.matchMedia('(prefers-reduced-motion: reduce)').matches
    } catch {
      return false
    }
  })

  const [progress, setProgress] = useState(0)
  const [glitching, setGlitching] = useState(false)
  const [done, setDone] = useState(false)
  const rafRef = useRef(null)
  const startRef = useRef(null)
  // Store DURATION in a ref so the progress useEffect captures it without
  // needing it in the dependency array (it won't change after mount).
  const durationRef = useRef(reduced ? 0 : 2800)

  // If reduced motion, complete immediately without any animation
  useEffect(() => {
    if (reduced) {
      onComplete?.()
    }
  }, [reduced, onComplete])

  // Progress bar
  useEffect(() => {
    if (reduced) return
    startRef.current = performance.now()
    const duration = durationRef.current
    function tick(now) {
      const elapsed = now - startRef.current
      const p = Math.min(elapsed / duration, 1)
      const eased = 1 - Math.pow(1 - p, 3)
      setProgress(Math.floor(eased * 100))
      if (p < 1) {
        rafRef.current = requestAnimationFrame(tick)
      } else {
        setProgress(100)
        setTimeout(() => {
          setDone(true)
          setTimeout(() => onComplete?.(), 600)
        }, 300)
      }
    }
    rafRef.current = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(rafRef.current)
  }, [reduced, onComplete])

  // Glitch
  useEffect(() => {
    if (reduced) return
    let timeout
    function schedule() {
      timeout = setTimeout(() => {
        setGlitching(true)
        setTimeout(() => { setGlitching(false); schedule() }, 80 + Math.random() * 120)
      }, Math.random() * 900 + 200)
    }
    schedule()
    return () => clearTimeout(timeout)
  }, [reduced])

  // Skip on click or Escape key
  const skip = () => {
    cancelAnimationFrame(rafRef.current)
    setDone(true)
    setTimeout(() => onComplete?.(), 300)
  }

  useEffect(() => {
    if (reduced) return
    const onKey = (e) => { if (e.key === 'Escape') skip() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [reduced]) // eslint-disable-line react-hooks/exhaustive-deps

  if (reduced) return null

  const glitchChars = '!@#$%^&*░▒▓█▄▀■□▪'
  const title = 'DreamServer'
  // Glitch chars are decorative — aria-label on the parent exposes the real name
  const displayTitle = glitching
    ? title.split('').map(ch =>
        Math.random() < 0.18 ? glitchChars[Math.floor(Math.random() * glitchChars.length)] : ch
      ).join('')
    : title

  return (
    <div
      role="status"
      aria-live="polite"
      aria-label="DreamServer is loading"
      aria-busy={!done}
      onClick={skip}
      style={{
        position: 'fixed', inset: 0, zIndex: 9999,
        background: '#000',
        display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
        overflow: 'hidden',
        opacity: done ? 0 : 1,
        transition: done ? 'opacity 0.6s ease' : 'none',
        pointerEvents: done ? 'none' : 'all',
        cursor: 'pointer',
      }}
    >
      {/* Decorative orb — hidden from assistive tech */}
      <div style={{ position: 'absolute', inset: 0, opacity: 0.75 }} aria-hidden="true">
        <OrbBackground reduced={reduced} />
      </div>

      {/* Content */}
      <div style={{
        position: 'relative', zIndex: 2,
        display: 'flex', flexDirection: 'column', alignItems: 'center',
        gap: '2rem', width: '100%', maxWidth: '520px', padding: '0 2rem',
      }}>
        {/* Glitch title — decorative spans are aria-hidden; real label is on root */}
        <div style={{ position: 'relative', userSelect: 'none' }} aria-hidden="true">
          {glitching && (
            <span style={{
              position: 'absolute', top: 0, left: '2px', color: '#f72585',
              fontFamily: "'JetBrains Mono','Courier New',monospace",
              fontSize: 'clamp(2rem,6vw,3.5rem)', fontWeight: 900, letterSpacing: '0.05em',
              clipPath: 'polygon(0 20%,100% 20%,100% 45%,0 45%)',
              opacity: 0.9, pointerEvents: 'none',
            }}>{displayTitle}</span>
          )}
          {glitching && (
            <span style={{
              position: 'absolute', top: 0, left: '-3px', color: '#4cc9f0',
              fontFamily: "'JetBrains Mono','Courier New',monospace",
              fontSize: 'clamp(2rem,6vw,3.5rem)', fontWeight: 900, letterSpacing: '0.05em',
              clipPath: 'polygon(0 60%,100% 60%,100% 80%,0 80%)',
              opacity: 0.85, pointerEvents: 'none',
            }}>{displayTitle}</span>
          )}
          <span style={{
            fontFamily: "'JetBrains Mono','Courier New',monospace",
            fontSize: 'clamp(2rem,6vw,3.5rem)', fontWeight: 900, letterSpacing: '0.05em',
            background: 'linear-gradient(135deg,#e4e4e7 0%,#a78bfa 50%,#4cc9f0 100%)',
            WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent',
            backgroundClip: 'text', display: 'inline-block',
            filter: glitching ? 'blur(0.5px)' : 'none', transition: 'filter 0.05s',
          }}>{displayTitle}</span>
        </div>

        <p style={{
          color: '#71717a', fontSize: '0.85rem', letterSpacing: '0.2em',
          textTransform: 'uppercase',
          fontFamily: "'JetBrains Mono','Courier New',monospace",
          margin: '-1.2rem 0 0',
        }}>Local AI Platform</p>

        {/* Progress — accessible via parent role="status" + aria-label */}
        <div style={{ width: '100%' }} aria-hidden="true">
          <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '0.5rem' }}>
            <span style={{ color: '#52525b', fontSize: '0.7rem', letterSpacing: '0.15em', textTransform: 'uppercase', fontFamily: 'monospace' }}>
              Initializing
            </span>
            <span style={{
              fontFamily: "'JetBrains Mono',monospace", fontSize: '0.8rem', fontWeight: 700,
              color: progress === 100 ? '#4cc9f0' : '#a78bfa', transition: 'color 0.3s',
            }}>{progress}%</span>
          </div>
          <div style={{ width: '100%', height: '3px', background: '#27272a', borderRadius: '999px', overflow: 'hidden', position: 'relative' }}>
            <div style={{
              position: 'absolute', left: 0, top: 0, height: '100%', width: `${progress}%`,
              background: 'linear-gradient(90deg,#7209b7,#4361ee,#4cc9f0)',
              borderRadius: '999px', transition: 'width 0.1s linear',
              boxShadow: '0 0 12px #4cc9f090',
            }} />
          </div>
        </div>

        {/* Skip hint */}
        <p style={{
          color: '#3f3f46', fontSize: '0.65rem', letterSpacing: '0.15em',
          textTransform: 'uppercase', fontFamily: 'monospace', margin: '-0.5rem 0 0',
        }}>
          Click or press Esc to skip
        </p>
      </div>
      {/* Google Fonts CDN removed — violates CSP font-src policy and leaks IPs.
          Font stack falls back to JetBrains Mono / Courier New (system). */}
    </div>
  )
}
