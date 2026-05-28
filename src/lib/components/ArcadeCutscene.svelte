<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import PinballMachine from './PinballMachine.svelte';

	let { oncomplete }: { oncomplete: () => void } = $props();

	const TOTAL_MS = 15000;
	let phase = $state<'title' | 'pinball' | 'loading' | 'welcome'>('title');
	let loadingPct = $state(0);
	let done = false;
	let timers: ReturnType<typeof setTimeout>[] = [];
	let loadingInterval: ReturnType<typeof setInterval> | null = null;

	function complete() {
		if (done) return;
		done = true;
		for (const t of timers) clearTimeout(t);
		if (loadingInterval) clearInterval(loadingInterval);
		oncomplete();
	}

	function skip() {
		complete();
	}

	function onKey(e: KeyboardEvent) {
		if (!done) {
			e.preventDefault();
			skip();
		}
	}

	onMount(() => {
		timers.push(setTimeout(() => (phase = 'pinball'), 3000));
		timers.push(
			setTimeout(() => {
				phase = 'loading';
				const start = Date.now();
				const duration = 3800;
				loadingInterval = setInterval(() => {
					const pct = Math.min(100, ((Date.now() - start) / duration) * 100);
					loadingPct = pct;
					if (pct >= 100 && loadingInterval) {
						clearInterval(loadingInterval);
						loadingInterval = null;
					}
				}, 60);
			}, 8000)
		);
		timers.push(setTimeout(() => (phase = 'welcome'), 12000));
		timers.push(setTimeout(complete, TOTAL_MS));

		window.addEventListener('keydown', onKey);
	});

	onDestroy(() => {
		for (const t of timers) clearTimeout(t);
		if (loadingInterval) clearInterval(loadingInterval);
		if (typeof window !== 'undefined') window.removeEventListener('keydown', onKey);
	});
</script>

<button type="button" class="cutscene" onclick={skip} aria-label="Skip intro">
	<div class="scanlines" aria-hidden="true"></div>
	<div class="crt-flicker" aria-hidden="true"></div>

	{#if phase === 'title'}
		<div class="stage stage-title">
			<div class="marquee">
				<div class="bulb-row top" aria-hidden="true">
					{#each Array(11) as _, i (i)}
						<span class="bulb" style="--i: {i};"></span>
					{/each}
				</div>
				<h1 class="title">CORALOGIX<br />ARCADE</h1>
				<div class="bulb-row bottom" aria-hidden="true">
					{#each Array(11) as _, i (i)}
						<span class="bulb" style="--i: {i};"></span>
					{/each}
				</div>
			</div>
			<p class="coin-prompt">INSERT COIN ▸ <span class="coin">$</span></p>
		</div>
	{:else if phase === 'pinball'}
		<div class="stage stage-pinball">
			<div class="pinball-hero">
				<PinballMachine variant="attract" showAiModule={true} />
			</div>
			<h2 class="tagline">AI IS NOW IN THE GAME</h2>
			<p class="tagline-sub">Every flipper. Every bumper. Every conversation.</p>
		</div>
	{:else if phase === 'loading'}
		<div class="stage stage-loading">
			<p class="terminal-line">&gt; SYSTEM: AI MODULE DETECTED</p>
			<p class="terminal-line delay-1">&gt; LOADING CORABOT v1.0<span class="cursor">_</span></p>
			<div
				class="progress"
				role="progressbar"
				aria-valuemin={0}
				aria-valuemax={100}
				aria-valuenow={Math.floor(loadingPct)}
			>
				<div class="progress-fill" style="width: {loadingPct}%;"></div>
			</div>
			<p class="progress-pct">{Math.floor(loadingPct)}%</p>
			<p class="terminal-line delay-2 muted">&gt; CONNECTING TO CORALOGIX AI CENTER...</p>
		</div>
	{:else}
		<div class="stage stage-welcome">
			<h2 class="welcome">WELCOME,<br />PLAYER</h2>
			<p class="welcome-sub">▸ Press any key to begin ◂</p>
		</div>
	{/if}

	<p class="skip-hint">PRESS ANY KEY TO SKIP</p>
</button>

<style>
	.cutscene {
		all: unset;
		position: fixed;
		inset: 0;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		background: var(--bg-dark);
		background-image:
			linear-gradient(rgba(57, 255, 142, 0.06) 1px, transparent 1px),
			linear-gradient(90deg, rgba(57, 255, 142, 0.06) 1px, transparent 1px);
		background-size: 16px 16px;
		color: var(--text);
		cursor: pointer;
		z-index: 9999;
		overflow: hidden;
		font-family: 'Press Start 2P', monospace;
		text-align: center;
	}

	.scanlines {
		position: absolute;
		inset: 0;
		pointer-events: none;
		background: repeating-linear-gradient(
			to bottom,
			rgba(0, 0, 0, 0) 0px,
			rgba(0, 0, 0, 0) 2px,
			rgba(0, 0, 0, 0.25) 2px,
			rgba(0, 0, 0, 0.25) 3px
		);
		z-index: 2;
	}
	.crt-flicker {
		position: absolute;
		inset: 0;
		pointer-events: none;
		background: rgba(57, 255, 142, 0.03);
		animation: flicker 0.18s steps(2) infinite;
		z-index: 3;
	}
	@keyframes flicker {
		0%, 100% { opacity: 1; }
		50% { opacity: 0.85; }
	}

	.stage {
		position: relative;
		z-index: 1;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 1.5rem;
		padding: 2rem;
		max-width: 90vw;
		animation: stage-in 0.35s steps(3) both;
	}
	@keyframes stage-in {
		from { opacity: 0; transform: translateY(8px); }
		to { opacity: 1; transform: translateY(0); }
	}

	/* ── Phase 1: Title ────────────────────────────────────────────── */
	.marquee {
		display: flex;
		flex-direction: column;
		align-items: stretch;
		gap: 0.6rem;
		padding: 1.5rem 2rem;
		background: var(--bg-card);
		border: 4px solid #000;
		box-shadow:
			0 0 0 4px var(--accent),
			0 0 32px rgba(57, 255, 142, 0.55),
			8px 8px 0 #000;
	}
	.title {
		font-family: 'Press Start 2P', monospace;
		font-size: clamp(1.8rem, 6vw, 3.5rem);
		line-height: 1.2;
		margin: 0;
		color: var(--accent);
		text-shadow:
			3px 3px 0 #000,
			6px 6px 0 var(--accent-hot);
		animation: title-flicker 1.4s steps(2) infinite;
		letter-spacing: 0.08em;
	}
	@keyframes title-flicker {
		0%, 92%, 100% { opacity: 1; }
		94%, 96% { opacity: 0.4; }
	}
	.bulb-row {
		display: flex;
		justify-content: space-between;
		gap: 0.25rem;
	}
	.bulb {
		width: 0.65rem;
		height: 0.65rem;
		background: var(--accent-lime);
		border: 2px solid #000;
		box-shadow: 0 0 6px var(--accent-lime);
		animation: bulb-chase 1.1s steps(11) infinite;
		animation-delay: calc(var(--i) * -0.1s);
	}
	@keyframes bulb-chase {
		0%, 18% { background: var(--accent-lime); box-shadow: 0 0 8px var(--accent-lime); }
		20%, 100% { background: var(--bg-panel); box-shadow: none; }
	}
	.coin-prompt {
		font-family: 'Press Start 2P', monospace;
		font-size: 0.85rem;
		color: var(--accent-cyan);
		margin: 0;
		animation: blink 0.9s steps(2, end) infinite;
		letter-spacing: 0.06em;
	}
	.coin {
		color: var(--accent-orange);
		display: inline-block;
		animation: coin-spin 0.6s steps(4) infinite;
	}
	@keyframes coin-spin {
		0%, 100% { transform: scaleX(1); }
		50% { transform: scaleX(-1); }
	}
	@keyframes blink {
		50% { opacity: 0.25; }
	}

	/* ── Phase 2: Pinball hero ─────────────────────────────────────── */
	.stage-pinball {
		flex-direction: column;
		gap: 1.5rem;
		align-items: center;
		text-align: center;
		max-width: min(40rem, 90vw);
	}
	.pinball-hero {
		width: clamp(180px, 28vh, 280px);
		animation: machine-drop 0.6s steps(5);
	}
	@keyframes machine-drop {
		0% { transform: translateY(-60px); opacity: 0; }
		70% { transform: translateY(8px); opacity: 1; }
		100% { transform: translateY(0); opacity: 1; }
	}
	.tagline {
		font-family: 'Press Start 2P', monospace;
		font-size: clamp(0.95rem, 2.4vw, 1.5rem);
		color: var(--accent);
		text-shadow: 3px 3px 0 #000;
		margin: 0;
		overflow: hidden;
		white-space: nowrap;
		border-right: 4px solid var(--accent);
		animation:
			typewriter 1.6s steps(21) 0.4s both,
			caret-blink 0.7s steps(2) 2s infinite;
		width: 23ch;
		max-width: 100%;
		padding-right: 0.25ch;
	}
	@keyframes typewriter {
		from { width: 0; }
		to { width: 23ch; }
	}
	@keyframes caret-blink {
		50% { border-color: transparent; }
	}
	.tagline-sub {
		font-family: 'VT323', monospace;
		font-size: clamp(1rem, 2.2vw, 1.4rem);
		color: var(--text-muted);
		margin: 0;
		opacity: 0;
		animation: fade-in 0.5s steps(3) 2.2s forwards;
	}
	@keyframes fade-in {
		from { opacity: 0; transform: translateY(4px); }
		to { opacity: 1; transform: translateY(0); }
	}

	/* ── Phase 3: Loading ──────────────────────────────────────────── */
	.stage-loading {
		gap: 0.85rem;
		align-items: flex-start;
		text-align: left;
		min-width: min(28rem, 90vw);
	}
	.terminal-line {
		font-family: 'Press Start 2P', monospace;
		font-size: 0.7rem;
		color: var(--accent);
		margin: 0;
		opacity: 0;
		animation: fade-in 0.3s steps(3) forwards;
	}
	.terminal-line.delay-1 { animation-delay: 0.4s; }
	.terminal-line.delay-2 { animation-delay: 1.2s; }
	.terminal-line.muted {
		color: var(--text-muted);
		font-size: 0.6rem;
	}
	.cursor {
		display: inline-block;
		animation: blink 0.6s steps(2, end) infinite;
		color: var(--accent);
	}
	.progress {
		width: 100%;
		height: 1.4rem;
		background: var(--bg-card);
		border: 3px solid #000;
		box-shadow: 3px 3px 0 #000, inset 0 0 0 2px var(--bg-panel);
		opacity: 0;
		animation: fade-in 0.3s steps(3) 0.8s forwards;
	}
	.progress-fill {
		height: 100%;
		background: var(--accent);
		background-image: repeating-linear-gradient(
			45deg,
			rgba(0, 0, 0, 0.15) 0px,
			rgba(0, 0, 0, 0.15) 4px,
			transparent 4px,
			transparent 8px
		);
		transition: width 80ms linear;
	}
	.progress-pct {
		font-family: 'Press Start 2P', monospace;
		font-size: 0.65rem;
		color: var(--accent-lime);
		margin: 0;
		align-self: flex-end;
		opacity: 0;
		animation: fade-in 0.3s steps(3) 0.8s forwards;
	}

	/* ── Phase 4: Welcome ──────────────────────────────────────────── */
	.welcome {
		font-family: 'Press Start 2P', monospace;
		font-size: clamp(1.6rem, 5vw, 3rem);
		color: var(--accent-lime);
		text-shadow:
			3px 3px 0 #000,
			6px 6px 0 var(--accent-hot);
		margin: 0;
		line-height: 1.2;
		letter-spacing: 0.08em;
		animation: welcome-bounce 0.6s steps(4);
	}
	@keyframes welcome-bounce {
		0% { transform: scale(0.4); opacity: 0; }
		60% { transform: scale(1.15); opacity: 1; }
		100% { transform: scale(1); opacity: 1; }
	}
	.welcome-sub {
		font-family: 'Press Start 2P', monospace;
		font-size: 0.7rem;
		color: var(--accent-cyan);
		margin: 0;
		animation: blink 0.7s steps(2, end) infinite;
		letter-spacing: 0.05em;
	}

	.skip-hint {
		position: absolute;
		bottom: 1.25rem;
		right: 1.25rem;
		font-family: 'Press Start 2P', monospace;
		font-size: 0.55rem;
		color: var(--text-muted);
		margin: 0;
		letter-spacing: 0.05em;
		z-index: 4;
		animation: blink 1.6s steps(2, end) infinite;
	}

	@media (prefers-reduced-motion: reduce) {
		.title, .coin-prompt, .coin, .bulb, .crt-flicker, .welcome-sub, .skip-hint, .tagline {
			animation: none !important;
		}
		.tagline { width: auto; border-right: none; }
	}
</style>
