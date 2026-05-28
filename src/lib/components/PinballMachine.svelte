<script lang="ts">
	let {
		variant = 'idle',
		showAiModule = true
	}: { variant?: 'idle' | 'attract' | 'tilt'; showAiModule?: boolean } = $props();
</script>

<div class="pinball" data-variant={variant} aria-hidden="true">
	<!--
		Pixel-art pinball cabinet.
		viewBox = 100 × 200 (width × height)
		Layout:
		  ─ Backboard        y=0  → y=70   (35%)
		  ─ Playfield        y=70 → y=170  (50%)
		  ─ Base + legs      y=170 → y=200 (15%)
	-->
	<svg
		class="cabinet"
		viewBox="0 0 126 200"
		shape-rendering="crispEdges"
		xmlns="http://www.w3.org/2000/svg"
	>
		<!-- ── BACKBOARD ────────────────────────────────────────── -->
		<!-- outer black frame -->
		<rect x="6" y="0" width="88" height="72" fill="#000" />
		<!-- inner panel -->
		<rect x="9" y="3" width="82" height="66" fill="#13302a" />
		<!-- top + bottom inner band -->
		<rect x="9" y="3" width="82" height="3" fill="#1d4a3b" />
		<rect x="9" y="66" width="82" height="3" fill="#1d4a3b" />

		<!-- Marquee bulbs (top + bottom of backboard) -->
		<g class="marquee-bulbs">
			{#each [0, 1, 2, 3, 4, 5, 6, 7] as i (i)}
				<rect
					class="mb"
					x={12 + i * 10}
					y="9"
					width="4"
					height="4"
					fill="#b6ff5a"
					style="--i: {i};"
				/>
			{/each}
			{#each [0, 1, 2, 3, 4, 5, 6, 7] as i (i)}
				<rect
					class="mb"
					x={12 + i * 10}
					y="57"
					width="4"
					height="4"
					fill="#b6ff5a"
					style="--i: {i + 8};"
				/>
			{/each}
		</g>

		<!-- Logo + subtitle using the real pixel font (clean & legible) -->
		<text
			x="50"
			y="32"
			text-anchor="middle"
			fill="#39ff8e"
			font-family="'Press Start 2P', monospace"
			font-size="9"
			font-weight="bold"
		>CORALOGIX</text>
		<text
			x="50"
			y="48"
			text-anchor="middle"
			fill="#7fffd4"
			font-family="'Press Start 2P', monospace"
			font-size="6"
		>ARCADE</text>

		<!-- Neck connecting backboard to body -->
		<rect x="14" y="69" width="72" height="6" fill="#000" />
		<rect x="16" y="71" width="68" height="4" fill="#1d4a3b" />

		<!-- ── CABINET BODY (with playfield) ─────────────────────── -->
		<rect x="4" y="74" width="92" height="100" fill="#000" />
		<rect x="6" y="76" width="88" height="96" fill="#13302a" />

		<!-- Playfield (slightly inset) -->
		<rect x="11" y="80" width="78" height="88" fill="#0a1f17" />
		<!-- neon playfield outline -->
		<rect x="11" y="80" width="78" height="1" fill="#39ff8e" opacity="0.6" />
		<rect x="11" y="167" width="78" height="1" fill="#39ff8e" opacity="0.6" />
		<rect x="11" y="80" width="1" height="88" fill="#39ff8e" opacity="0.6" />
		<rect x="88" y="80" width="1" height="88" fill="#39ff8e" opacity="0.6" />

		<!-- Subtle playfield arc (lane guides) -->
		<path d="M 11 92 Q 50 84 89 92" fill="none" stroke="#1d4a3b" stroke-width="1" />
		<path d="M 14 100 Q 50 92 86 100" fill="none" stroke="#1d4a3b" stroke-width="1" />

		<!-- Plunger lane on the right -->
		<rect x="83" y="92" width="3" height="72" fill="#1d4a3b" />
		<rect x="83" y="92" width="3" height="1" fill="#000" />
		<rect x="83" y="164" width="3" height="1" fill="#000" />
		<!-- plunger spring tip -->
		<rect x="83" y="158" width="3" height="2" fill="#ffaa00" />

		<!-- Bumpers (3-pointed star arrangement near top) -->
		<g class="bumper bumper-1">
			<circle cx="30" cy="108" r="5" fill="#000" />
			<circle cx="30" cy="108" r="4" fill="#ffaa00" />
			<circle cx="30" cy="108" r="2" fill="#fff7b3" />
		</g>
		<g class="bumper bumper-2">
			<circle cx="65" cy="108" r="5" fill="#000" />
			<circle cx="65" cy="108" r="4" fill="#ff3838" />
			<circle cx="65" cy="108" r="2" fill="#ffd6d6" />
		</g>
		<g class="bumper bumper-3">
			<circle cx="48" cy="128" r="5" fill="#000" />
			<circle cx="48" cy="128" r="4" fill="#7fffd4" />
			<circle cx="48" cy="128" r="2" fill="#ffffff" />
		</g>

		<!-- Slingshot triangles above flippers -->
		<polygon points="16,148 26,148 16,158" fill="#1d4a3b" stroke="#000" stroke-width="1" />
		<polygon points="64,148 74,148 74,158" fill="#1d4a3b" stroke="#000" stroke-width="1" />

		<!-- Flippers (V shape near bottom) -->
		<g class="flipper flipper-left">
			<rect x="18" y="160" width="16" height="3" fill="#000" />
			<rect x="19" y="161" width="15" height="2" fill="#39ff8e" />
		</g>
		<g class="flipper flipper-right">
			<rect x="56" y="160" width="16" height="3" fill="#000" />
			<rect x="56" y="161" width="15" height="2" fill="#39ff8e" />
		</g>

		<!-- Drain gap label (small "OUT" hole between flippers) -->
		<rect x="40" y="164" width="10" height="4" fill="#000" />
		<rect x="41" y="165" width="8" height="2" fill="#3a3a3a" />

		<!-- Ball (animated via CSS transform on .ball) -->
		<g class="ball">
			<circle cx="0" cy="0" r="3" fill="#000" />
			<circle cx="0" cy="0" r="2.2" fill="#ffffff" />
			<circle cx="-0.5" cy="-0.5" r="0.7" fill="#b3ffe0" />
		</g>

		<!-- ── AI MODULE (retrofitted CRT display bolted to the side) ── -->
		{#if showAiModule}
			<g class="ai-module">
				<!-- mounting brackets connecting module to cabinet -->
				<rect x="96" y="96" width="4" height="4" fill="#000" />
				<rect x="96" y="118" width="4" height="4" fill="#000" />
				<rect x="96" y="140" width="4" height="4" fill="#000" />

				<!-- module bezel (outer chassis) -->
				<rect x="98" y="86" width="26" height="62" fill="#000" />
				<rect x="100" y="88" width="22" height="58" fill="#1d4a3b" />
				<!-- bezel highlight -->
				<rect x="100" y="88" width="22" height="2" fill="#2a6a55" />
				<!-- corner screws -->
				<rect x="101" y="89" width="2" height="2" fill="#000" />
				<rect x="119" y="89" width="2" height="2" fill="#000" />
				<rect x="101" y="143" width="2" height="2" fill="#000" />
				<rect x="119" y="143" width="2" height="2" fill="#000" />

				<!-- CRT screen recess -->
				<rect x="103" y="93" width="16" height="28" fill="#000" />
				<rect x="104" y="94" width="14" height="26" fill="#0a1f17" />

				<!-- glowing AI text inside screen -->
				<text
					class="ai-text"
					x="111"
					y="110"
					text-anchor="middle"
					fill="#39ff8e"
					font-family="'Press Start 2P', monospace"
					font-size="6.4"
					font-weight="bold"
				>AI</text>

				<!-- screen scanlines -->
				<rect x="104" y="100" width="14" height="1" fill="#39ff8e" opacity="0.12" />
				<rect x="104" y="108" width="14" height="1" fill="#39ff8e" opacity="0.12" />
				<rect x="104" y="116" width="14" height="1" fill="#39ff8e" opacity="0.12" />

				<!-- speaker grille below screen -->
				<rect x="103" y="125" width="16" height="6" fill="#000" />
				<rect x="105" y="127" width="2" height="2" fill="#1d4a3b" />
				<rect x="109" y="127" width="2" height="2" fill="#1d4a3b" />
				<rect x="113" y="127" width="2" height="2" fill="#1d4a3b" />

				<!-- status LEDs at the bottom -->
				<rect class="ai-led" x="104" y="135" width="3" height="3" fill="#39ff8e" />
				<rect class="ai-led d2" x="110" y="135" width="3" height="3" fill="#7fffd4" />
				<rect class="ai-led d3" x="116" y="135" width="3" height="3" fill="#ffaa00" />
			</g>
		{/if}

		<!-- ── BASE + LEGS ──────────────────────────────────────── -->
		<rect x="4" y="170" width="92" height="6" fill="#000" />
		<rect x="6" y="172" width="88" height="2" fill="#1d4a3b" />
		<!-- legs -->
		<rect x="10" y="176" width="8" height="22" fill="#000" />
		<rect x="82" y="176" width="8" height="22" fill="#000" />
		<rect x="11" y="177" width="6" height="20" fill="#3a3a3a" />
		<rect x="83" y="177" width="6" height="20" fill="#3a3a3a" />
		<!-- foot caps -->
		<rect x="8" y="195" width="12" height="3" fill="#000" />
		<rect x="80" y="195" width="12" height="3" fill="#000" />

		<!-- ── TILT OVERLAY ─────────────────────────────────────── -->
		{#if variant === 'tilt'}
			<g class="tilt-overlay">
				<rect x="18" y="115" width="64" height="18" fill="#000" />
				<rect x="20" y="117" width="60" height="14" fill="#ff3838" />
				<text
					x="50"
					y="128"
					text-anchor="middle"
					fill="#000"
					font-family="'Press Start 2P', monospace"
					font-size="10"
					font-weight="bold"
				>TILT!</text>
			</g>
		{/if}
	</svg>
</div>

<style>
	.pinball {
		display: inline-block;
		width: 100%;
		filter: drop-shadow(4px 4px 0 #000);
	}
	.cabinet {
		display: block;
		width: 100%;
		height: auto;
		/* Keep edges crisp on most rects, but allow circles/text to use subpixel AA */
	}

	/* ── Marquee bulbs chase ─────────────────────────────────── */
	.mb {
		animation: bulb-pulse 1.2s steps(2) infinite;
		animation-delay: calc(var(--i, 0) * -0.08s);
	}
	@keyframes bulb-pulse {
		0%, 50% { fill: #b6ff5a; opacity: 1; }
		50.01%, 100% { fill: #1d4a3b; opacity: 0.5; }
	}

	/* ── Bumpers flash when ball hits ────────────────────────── */
	.bumper {
		animation: bumper-flash 2.4s steps(2) infinite;
		transform-box: fill-box;
		transform-origin: center;
	}
	.bumper-1 { animation-delay: 0s; }
	.bumper-2 { animation-delay: 0.8s; }
	.bumper-3 { animation-delay: 1.6s; }
	@keyframes bumper-flash {
		0%, 8% { filter: brightness(1.7); }
		8.01%, 100% { filter: brightness(1); }
	}

	/* ── Flippers tap independently ──────────────────────────── */
	.flipper-left {
		transform-origin: 20px 162px;
		animation: flip-left 2.4s steps(3) infinite;
	}
	.flipper-right {
		transform-origin: 70px 162px;
		animation: flip-right 2.4s steps(3) infinite;
	}
	@keyframes flip-left {
		0%, 92% { transform: rotate(0deg); }
		94% { transform: rotate(-22deg); }
		96% { transform: rotate(-12deg); }
		98%, 100% { transform: rotate(0deg); }
	}
	@keyframes flip-right {
		0%, 42% { transform: rotate(0deg); }
		44% { transform: rotate(22deg); }
		46% { transform: rotate(12deg); }
		48%, 100% { transform: rotate(0deg); }
	}

	/* ── Ball trajectory ─────────────────────────────────────── */
	.ball {
		animation: ball-path 2.4s ease-in-out infinite;
	}
	@keyframes ball-path {
		0%   { transform: translate(50px, 95px); }
		10%  { transform: translate(30px, 108px); }
		18%  { transform: translate(48px, 128px); }
		28%  { transform: translate(65px, 108px); }
		38%  { transform: translate(48px, 128px); }
		48%  { transform: translate(25px, 150px); }
		56%  { transform: translate(32px, 158px); }
		64%  { transform: translate(50px, 150px); }
		72%  { transform: translate(68px, 158px); }
		80%  { transform: translate(75px, 150px); }
		90%  { transform: translate(60px, 110px); }
		100% { transform: translate(50px, 95px); }
	}

	/* ── AI module LEDs blink ────────────────────────────────── */
	.ai-led { animation: led-blink 0.9s steps(2) infinite; }
	.ai-led.d2 { animation-delay: -0.3s; }
	.ai-led.d3 { animation-delay: -0.6s; }
	@keyframes led-blink {
		0%, 55% { opacity: 1; }
		55.01%, 100% { opacity: 0.25; }
	}

	/* ── AI screen text pulses ──────────────────────────────── */
	.ai-text {
		animation: ai-pulse 1.6s steps(2) infinite;
	}
	@keyframes ai-pulse {
		0%, 70% {
			fill: #39ff8e;
			filter: drop-shadow(0 0 2px #39ff8e);
		}
		70.01%, 100% {
			fill: #7fffd4;
			filter: none;
		}
	}

	/* ── Tilt variant ────────────────────────────────────────── */
	.pinball[data-variant='tilt'] .cabinet {
		animation: shake 0.16s steps(2) infinite;
	}
	@keyframes shake {
		0%, 100% { transform: translate(0, 0); }
		25% { transform: translate(-3px, 2px); }
		75% { transform: translate(3px, -2px); }
	}
	.tilt-overlay {
		animation: blink-tilt 0.4s steps(2) infinite;
	}
	@keyframes blink-tilt {
		0%, 50% { opacity: 1; }
		50.01%, 100% { opacity: 0.4; }
	}

	@media (prefers-reduced-motion: reduce) {
		.mb, .bumper, .flipper-left, .flipper-right, .ball, .ai-led, .cabinet, .tilt-overlay {
			animation: none !important;
		}
	}
</style>
