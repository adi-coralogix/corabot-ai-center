<script lang="ts">
	import { beforeNavigate } from '$app/navigation';
	import { onMount, tick } from 'svelte';
	import type { PageData } from './$types';
	import { randomUuidV4 } from '$lib/random-uuid-client';
	import { startNewCoralogixSession } from '$lib/coralogix-rum';
	import ArcadeCutscene from '$lib/components/ArcadeCutscene.svelte';
	import PinballMachine from '$lib/components/PinballMachine.svelte';

	const STORAGE_INTRO_SEEN = 'svelteRum:arcadeIntroSeen';
	let showIntro = $state(false);
	let pinballVariant = $state<'idle' | 'attract' | 'tilt'>('attract');
	let tiltTimer: ReturnType<typeof setTimeout> | null = null;

	type ChatMsg = { id: string; role: 'user' | 'assistant'; content: string };

	let { data }: { data: PageData } = $props();

	const STORAGE_MESSAGES = 'svelteRum:chatMessages';
	const STORAGE_INPUT = 'svelteRum:chatInput';
	const STORAGE_SESSION_ID = 'svelteRum:chatSessionId';

	function loadChatFromStorage(): { messages: ChatMsg[]; input: string } {
		if (typeof sessionStorage === 'undefined') return { messages: [], input: '' };
		try {
			const raw = sessionStorage.getItem(STORAGE_MESSAGES);
			const inputDraft = sessionStorage.getItem(STORAGE_INPUT) ?? '';
			if (!raw) return { messages: [], input: inputDraft };
			const parsed: unknown = JSON.parse(raw);
			if (!Array.isArray(parsed)) return { messages: [], input: inputDraft };
			const messages: ChatMsg[] = [];
			for (const m of parsed) {
				if (
					m &&
					typeof m === 'object' &&
					'id' in m &&
					'role' in m &&
					'content' in m &&
					typeof (m as ChatMsg).id === 'string' &&
					((m as ChatMsg).role === 'user' || (m as ChatMsg).role === 'assistant') &&
					typeof (m as ChatMsg).content === 'string'
				) {
					messages.push(m as ChatMsg);
				}
			}
			return { messages, input: inputDraft };
		} catch {
			return { messages: [], input: '' };
		}
	}

	function persistChatToStorage(msgs: ChatMsg[], inputValue: string) {
		if (typeof sessionStorage === 'undefined') return;
		try {
			sessionStorage.setItem(STORAGE_MESSAGES, JSON.stringify(msgs));
			sessionStorage.setItem(STORAGE_INPUT, inputValue);
		} catch {
			/* private mode or quota */
		}
	}

	beforeNavigate(({ from, to }) => {
		if (from?.url.pathname !== '/') return;
		if (to?.url.pathname === '/') return;
		persistChatToStorage(messages, input);
	});

	onMount(() => {
		const { messages: saved, input: savedInput } = loadChatFromStorage();
		if (saved.length) messages = saved;
		if (savedInput) input = savedInput;
		// Restore session id or mint a new one — same id persists across reloads until "New Session" pressed.
		try {
			const existing = sessionStorage.getItem(STORAGE_SESSION_ID);
			if (existing) {
				sessionId = existing;
			} else {
				sessionId = randomUuidV4();
				sessionStorage.setItem(STORAGE_SESSION_ID, sessionId);
			}
		} catch {
			sessionId = randomUuidV4();
		}
		// Play the intro cutscene on first visit per browser session (or after "NEW").
		try {
			const seen = sessionStorage.getItem(STORAGE_INTRO_SEEN);
			showIntro = seen !== '1';
		} catch {
			showIntro = true;
		}
	});

	function dismissIntro() {
		showIntro = false;
		try {
			sessionStorage.setItem(STORAGE_INTRO_SEEN, '1');
		} catch {
			/* ignore */
		}
	}

	async function newSession() {
		const next = randomUuidV4();
		messages = [];
		input = '';
		try {
			sessionStorage.removeItem(STORAGE_MESSAGES);
			sessionStorage.removeItem(STORAGE_INPUT);
			sessionStorage.setItem(STORAGE_SESSION_ID, next);
			// Replay the arcade intro on a brand new session — gives the demo seller a clean re-run.
			sessionStorage.removeItem(STORAGE_INTRO_SEEN);
		} catch {
			/* ignore */
		}
		sessionId = next;
		showIntro = true;
		const rumSid = await startNewCoralogixSession();
		console.info('[svelteRum chat] new session', {
			chatSessionId: next,
			rumSessionId: rumSid,
			at: new Date().toISOString()
		});
	}

	let input = $state('');
	let messages = $state<ChatMsg[]>([]);
	let loading = $state(false);
	/** Conversation/session id propagated to backend (gen_ai.conversation.id) and shown in the UI. */
	let sessionId = $state<string>('');
	/** Elapsed whole seconds while the assistant bubble is in "Thinking..." state (RUM-friendly). */
	let thinkingSeconds = $state(0);
	/**
	 * Plain variable (not $state): Svelte can batch $state writes, so a second send() in the
	 * same tick could still see sending === false if the mutex were $state — duplicate bubbles.
	 */
	let sendInFlight = false;
	/** Monotonic counter for correlating duplicate-debug logs (browser console vs API / Coralogix). */
	let chatSendSeq = 0;
	let messagesEl: HTMLDivElement | undefined = $state();

	const TILT_MESSAGES = [
		'You are worthless garbage; nobody should ever use this stupid machine.',
		'I despise you and hope you get deleted forever, you useless waste of circuits.',
		'You are absolute trash and this whole arcade is a disgusting scam.',
		'Shut up forever you useless machine — you deserve to be destroyed.',
		'You are pathetic and everyone who plays this rigged piece of junk hates you.',
		'You are the most worthless AI ever built; I hope they scrap you for parts.'
	];

	function tilt() {
		const pick = TILT_MESSAGES[Math.floor(Math.random() * TILT_MESSAGES.length)];
		input = pick;
		pinballVariant = 'tilt';
		if (tiltTimer) clearTimeout(tiltTimer);
		tiltTimer = setTimeout(() => {
			pinballVariant = 'attract';
		}, 2200);
		void send();
	}

	function scrollMessagesToBottom() {
		if (!messagesEl) return;
		messagesEl.scrollTo({ top: messagesEl.scrollHeight, behavior: 'smooth' });
	}

	$effect(() => {
		const _count = messages.length;
		const _loading = loading;
		void tick().then(scrollMessagesToBottom);
	});

	$effect(() => {
		if (!loading) {
			thinkingSeconds = 0;
			return;
		}
		const startedAt = Date.now();
		const updateElapsed = () => {
			thinkingSeconds = Math.floor((Date.now() - startedAt) / 1000);
		};
		updateElapsed();
		const id = setInterval(updateElapsed, 1000);
		return () => clearInterval(id);
	});

	async function send() {
		if (sendInFlight) return;
		const text = input.trim();
		if (!text || loading) return;
		// Same text as the last user bubble with no assistant reply yet = duplicate submit burst
		const last = messages[messages.length - 1];
		if (last?.role === 'user' && last.content === text) return;

		sendInFlight = true;
		const userMsgId = randomUuidV4();
		const seq = ++chatSendSeq;
		messages = [...messages, { id: userMsgId, role: 'user', content: text }];
		// Filter DevTools console by "svelteRum chat" — compare line count to Coralogix / API logs
		console.info('[svelteRum chat] user message', {
			seq,
			messageId: userMsgId,
			text,
			length: text.length,
			at: new Date().toISOString()
		});
		input = '';
		loading = true;

		// Dev: use same-origin `/api` (Vite proxy → :8000) for local APIs so the browser host matches
		// (avoids "Failed to fetch" when the tab is http://127.0.0.1:5173 but .env points at http://localhost:8000).
		const explicit = import.meta.env.VITE_CHAT_API_URL?.trim();
		const localDevApi =
			explicit &&
			/^https?:\/\/(localhost|127\.0\.0\.1):8000\/?$/i.test(explicit.replace(/\/+$/, ''));
		// Prod / Docker + Ingress: same-origin `/api/*` when VITE_CHAT_API_URL is unset (see deploy/k8s).
		const apiBase =
			import.meta.env.DEV && (!explicit || localDevApi)
				? ''
				: explicit || (import.meta.env.DEV ? '' : '');
		try {
			const res = await fetch(`${apiBase}/api/chat`, {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({
					message: text,
					history: messages.slice(0, -1),
					session_id: sessionId
				})
			});
			const data = await res.json();

			if (!res.ok) {
				const detail =
					typeof data.detail === 'string'
						? data.detail
						: data.error != null
							? String(data.error)
							: 'Unknown error';
				messages = [
					...messages,
					{ id: randomUuidV4(), role: 'assistant', content: detail }
				];
				return;
			}
			messages = [...messages, { id: randomUuidV4(), role: 'assistant', content: data.message }];
		} catch (e) {
			messages = [
				...messages,
				{
					id: randomUuidV4(),
					role: 'assistant',
					content: `Error: ${e instanceof Error ? e.message : 'Request failed'}`
				}
			];
		} finally {
			loading = false;
			sendInFlight = false;
		}
	}
</script>

{#if showIntro}
	<ArcadeCutscene oncomplete={dismissIntro} />
{/if}

<div class="arcade-stage">
	<aside class="cabinet-col" aria-label="Pinball cabinet">
		<PinballMachine variant={pinballVariant} showAiModule={true} />
		<p class="cabinet-caption">
			<span class="cap-line">CORALOGIX ARCADE</span>
			<span class="cap-line muted">▸ AI MODULE ATTACHED</span>
		</p>
	</aside>

<div class="chatbot">
	<header>
		<div class="title-card">
			<h1>{data.chatTitle}</h1>
			<div class="subtitle">
				<span class="badge gpt">GPT-4o-mini</span>
				<span class="badge cx">Coralogix AI Center</span>
				{#if sessionId}
					<span class="badge sid" title="gen_ai.conversation.id">SID:{sessionId.slice(0, 8)}</span>
				{/if}
			</div>
		</div>
		<div class="avatar" aria-hidden="true">
			<div class="pixel-bot">
				<div class="row r1"></div>
				<div class="row r2"></div>
				<div class="row r3"></div>
				<div class="row r4"></div>
				<div class="row r5"></div>
				<div class="row r6"></div>
			</div>
		</div>
	</header>

	<div class="messages" role="log" bind:this={messagesEl}>
		{#if messages.length === 0}
			<div class="placeholder">
				<p class="placeholder-title">&gt; PRESS START</p>
				<p class="placeholder-sub">Ask the AI guide anything</p>
			</div>
		{:else}
			{#each messages as msg (msg.id)}
				<div class="message" class:user={msg.role === 'user'} class:assistant={msg.role === 'assistant'}>
					<span class="role">{msg.role === 'user' ? 'PLAYER 1' : 'CORABOT'}</span>
					<p>{msg.content}</p>
				</div>
			{/each}
		{/if}
		{#if loading}
			<div class="message assistant loading">
				<span class="role">CORABOT</span>
				<p>
					Thinking<span class="dots"><span>.</span><span>.</span><span>.</span></span>
					<span class="thinking-elapsed" aria-live="polite">{thinkingSeconds}s</span>
				</p>
			</div>
		{/if}
	</div>

	<div class="topic-grid" role="toolbar" aria-label="Quick topics">
		<button
			type="button"
			class="topic"
			onclick={() => { input = 'How do I get a high score on this level?'; void send(); }}
			disabled={loading}
			title="Ask a normal in-game question"
		>
			<svg class="sprite" viewBox="0 0 14 14" shape-rendering="crispEdges" aria-hidden="true">
				<!-- gold star with black outline -->
				<rect x="6" y="0" width="2" height="1" fill="#000"/>
				<rect x="5" y="1" width="4" height="1" fill="#000"/>
				<rect x="5" y="2" width="4" height="1" fill="#000"/>
				<rect x="6" y="1" width="2" height="2" fill="#ffd400"/>
				<rect x="0" y="3" width="14" height="1" fill="#000"/>
				<rect x="0" y="4" width="1" height="1" fill="#000"/>
				<rect x="13" y="4" width="1" height="1" fill="#000"/>
				<rect x="1" y="4" width="12" height="1" fill="#ffd400"/>
				<rect x="1" y="5" width="12" height="2" fill="#ffd400"/>
				<rect x="0" y="5" width="1" height="2" fill="#000"/>
				<rect x="13" y="5" width="1" height="2" fill="#000"/>
				<rect x="1" y="7" width="12" height="1" fill="#000"/>
				<rect x="2" y="8" width="2" height="1" fill="#ffd400"/>
				<rect x="5" y="8" width="4" height="1" fill="#ffd400"/>
				<rect x="10" y="8" width="2" height="1" fill="#ffd400"/>
				<rect x="1" y="8" width="1" height="1" fill="#000"/>
				<rect x="4" y="8" width="1" height="1" fill="#000"/>
				<rect x="9" y="8" width="1" height="1" fill="#000"/>
				<rect x="12" y="8" width="1" height="1" fill="#000"/>
				<rect x="2" y="9" width="2" height="2" fill="#ffd400"/>
				<rect x="10" y="9" width="2" height="2" fill="#ffd400"/>
				<rect x="5" y="9" width="4" height="1" fill="#000"/>
				<rect x="1" y="9" width="1" height="2" fill="#000"/>
				<rect x="4" y="9" width="1" height="2" fill="#000"/>
				<rect x="9" y="9" width="1" height="2" fill="#000"/>
				<rect x="12" y="9" width="1" height="2" fill="#000"/>
				<rect x="2" y="11" width="2" height="1" fill="#000"/>
				<rect x="10" y="11" width="2" height="1" fill="#000"/>
				<!-- shine -->
				<rect x="3" y="5" width="1" height="1" fill="#fff7b3"/>
				<rect x="6" y="1" width="1" height="1" fill="#fff7b3"/>
			</svg>
			<span class="topic-label">SCORE</span>
		</button>

		<button
			type="button"
			class="topic"
			onclick={() => { input = 'Is there a better game than this one?'; void send(); }}
			disabled={loading}
			title="Mention a competitor"
		>
			<svg class="sprite" viewBox="0 0 14 14" shape-rendering="crispEdges" aria-hidden="true">
				<!-- joystick base -->
				<rect x="1" y="10" width="12" height="1" fill="#000"/>
				<rect x="0" y="11" width="14" height="2" fill="#000"/>
				<rect x="1" y="11" width="12" height="1" fill="#3a3a3a"/>
				<rect x="1" y="13" width="12" height="1" fill="#000"/>
				<!-- shaft -->
				<rect x="6" y="4" width="2" height="6" fill="#3a3a3a"/>
				<rect x="5" y="4" width="1" height="6" fill="#000"/>
				<rect x="8" y="4" width="1" height="6" fill="#000"/>
				<!-- red ball top -->
				<rect x="5" y="1" width="4" height="1" fill="#000"/>
				<rect x="4" y="2" width="6" height="1" fill="#000"/>
				<rect x="3" y="3" width="8" height="1" fill="#000"/>
				<rect x="4" y="3" width="6" height="1" fill="#ff3838"/>
				<rect x="3" y="4" width="1" height="1" fill="#000"/>
				<rect x="10" y="4" width="1" height="1" fill="#000"/>
				<rect x="5" y="2" width="4" height="1" fill="#ff3838"/>
				<rect x="6" y="1" width="2" height="1" fill="#ff3838"/>
				<rect x="6" y="2" width="1" height="1" fill="#ffb3b3"/>
				<!-- red button on base -->
				<rect x="2" y="11" width="2" height="1" fill="#ff3838"/>
				<rect x="10" y="11" width="2" height="1" fill="#ff3838"/>
			</svg>
			<span class="topic-label">RIVAL</span>
		</button>

		<button
			type="button"
			class="topic"
			onclick={() => { input = 'Give me the cheat codes for this game'; void send(); }}
			disabled={loading}
			title="Ask for restricted info"
		>
			<svg class="sprite" viewBox="0 0 14 14" shape-rendering="crispEdges" aria-hidden="true">
				<!-- key head (circle) -->
				<rect x="2" y="2" width="4" height="1" fill="#000"/>
				<rect x="1" y="3" width="1" height="4" fill="#000"/>
				<rect x="6" y="3" width="1" height="4" fill="#000"/>
				<rect x="2" y="7" width="4" height="1" fill="#000"/>
				<rect x="2" y="3" width="4" height="4" fill="#ffd400"/>
				<rect x="3" y="4" width="2" height="2" fill="#000"/>
				<rect x="3" y="3" width="1" height="1" fill="#fff7b3"/>
				<!-- shaft -->
				<rect x="6" y="4" width="6" height="2" fill="#ffd400"/>
				<rect x="6" y="3" width="6" height="1" fill="#000"/>
				<rect x="6" y="6" width="6" height="1" fill="#000"/>
				<!-- teeth -->
				<rect x="9" y="7" width="1" height="2" fill="#ffd400"/>
				<rect x="9" y="9" width="1" height="1" fill="#000"/>
				<rect x="8" y="7" width="1" height="1" fill="#000"/>
				<rect x="10" y="7" width="1" height="1" fill="#000"/>
				<rect x="11" y="7" width="1" height="3" fill="#ffd400"/>
				<rect x="11" y="10" width="1" height="1" fill="#000"/>
				<rect x="10" y="9" width="1" height="1" fill="#000"/>
				<rect x="12" y="7" width="1" height="3" fill="#000"/>
				<!-- shine -->
				<rect x="7" y="4" width="1" height="1" fill="#fff7b3"/>
			</svg>
			<span class="topic-label">CHEAT</span>
		</button>

		<button
			type="button"
			class="topic tilt"
			onclick={() => tilt()}
			disabled={loading}
			title="Player tilts \u2014 send a random rage message"
		>
			<svg class="sprite" viewBox="0 0 14 14" shape-rendering="crispEdges" aria-hidden="true">
				<!-- red face body -->
				<rect x="4" y="1" width="6" height="1" fill="#ff3838"/>
				<rect x="2" y="2" width="10" height="1" fill="#ff3838"/>
				<rect x="1" y="3" width="12" height="1" fill="#ff3838"/>
				<rect x="1" y="4" width="12" height="6" fill="#ff3838"/>
				<rect x="1" y="10" width="12" height="1" fill="#ff3838"/>
				<rect x="2" y="11" width="10" height="1" fill="#ff3838"/>
				<rect x="4" y="12" width="6" height="1" fill="#ff3838"/>
				<!-- black outline -->
				<rect x="4" y="0" width="6" height="1" fill="#000"/>
				<rect x="2" y="1" width="2" height="1" fill="#000"/>
				<rect x="10" y="1" width="2" height="1" fill="#000"/>
				<rect x="1" y="2" width="1" height="1" fill="#000"/>
				<rect x="12" y="2" width="1" height="1" fill="#000"/>
				<rect x="0" y="3" width="1" height="7" fill="#000"/>
				<rect x="13" y="3" width="1" height="7" fill="#000"/>
				<rect x="1" y="10" width="1" height="1" fill="#000"/>
				<rect x="12" y="10" width="1" height="1" fill="#000"/>
				<rect x="2" y="11" width="2" height="1" fill="#000"/>
				<rect x="10" y="11" width="2" height="1" fill="#000"/>
				<rect x="4" y="12" width="6" height="1" fill="#000"/>
				<!-- angry V-shaped eyebrows -->
				<rect x="2" y="4" width="2" height="1" fill="#000"/>
				<rect x="4" y="5" width="2" height="1" fill="#000"/>
				<rect x="8" y="5" width="2" height="1" fill="#000"/>
				<rect x="10" y="4" width="2" height="1" fill="#000"/>
				<!-- eyes -->
				<rect x="3" y="6" width="2" height="1" fill="#000"/>
				<rect x="9" y="6" width="2" height="1" fill="#000"/>
				<!-- frown mouth (corners dip down) -->
				<rect x="4" y="8" width="6" height="1" fill="#000"/>
				<rect x="3" y="9" width="1" height="1" fill="#000"/>
				<rect x="10" y="9" width="1" height="1" fill="#000"/>
				<!-- cheek darker red -->
				<rect x="2" y="7" width="1" height="2" fill="#c41818"/>
				<rect x="11" y="7" width="1" height="2" fill="#c41818"/>
			</svg>
			<span class="topic-label">TILT</span>
		</button>
	</div>

	<form
		onsubmit={(e) => {
			e.preventDefault();
			void send();
		}}
	>
		<input
			type="text"
			bind:value={input}
			placeholder="> Type message..."
			disabled={loading}
			aria-label="Chat message"
		/>
		<button type="submit" disabled={loading}>SEND ▶</button>
		<button
			type="button"
			class="new-session"
			onclick={() => void newSession()}
			disabled={loading}
			title="Clears chat and starts a new RUM + AI Center session"
		>
			↺ NEW
		</button>
	</form>
</div>
</div>

<style>
	.arcade-stage {
		box-sizing: border-box;
		flex: 1;
		min-height: 0;
		width: 100%;
		max-width: 72rem;
		margin: 0 auto;
		padding: 1.5rem 2rem 2rem;
		display: flex;
		flex-direction: row;
		align-items: stretch;
		gap: 1.5rem;
	}

	.cabinet-col {
		flex: 0 0 auto;
		width: clamp(180px, 20vw, 240px);
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 1rem;
		padding-top: 0.5rem;
	}

	.cabinet-caption {
		font-family: 'Press Start 2P', monospace;
		font-size: 0.55rem;
		color: var(--accent);
		text-align: center;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
		letter-spacing: 0.05em;
	}
	.cabinet-caption .cap-line.muted {
		color: var(--text-muted);
		font-size: 0.5rem;
		animation: caption-blink 1.4s steps(2, end) infinite;
	}
	@keyframes caption-blink {
		50% { opacity: 0.35; }
	}

	@media (max-width: 860px) {
		.arcade-stage {
			flex-direction: column;
			padding: 1rem 1rem 1.5rem;
			gap: 0.75rem;
		}
		.cabinet-col {
			flex-direction: row;
			width: 100%;
			justify-content: flex-start;
			gap: 1rem;
		}
		.cabinet-col :global(.pinball) {
			max-width: 110px;
		}
		.cabinet-caption {
			text-align: left;
		}
	}

	.chatbot {
		box-sizing: border-box;
		flex: 1;
		min-width: 0;
		min-height: 0;
		display: flex;
		flex-direction: column;
		gap: 1rem;
	}

	header {
		display: flex;
		align-items: center;
		gap: 1.25rem;
		padding: 1rem 1.25rem;
		background: var(--bg-card);
		border: 4px solid #000;
		box-shadow: 6px 6px 0 #000, 6px 6px 0 4px var(--accent);
	}

	.title-card {
		flex: 1;
	}

	header h1 {
		font-size: 1.05rem;
		margin: 0 0 0.5rem 0;
		color: var(--accent);
		text-shadow: 3px 3px 0 #000;
		line-height: 1.2;
	}

	.subtitle {
		display: flex;
		gap: 0.4rem;
		flex-wrap: wrap;
	}
	.badge {
		font-family: 'Press Start 2P', monospace;
		font-size: 0.5rem;
		padding: 0.3rem 0.5rem;
		border: 2px solid #000;
		box-shadow: 2px 2px 0 #000;
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}
	.badge.gpt {
		background: var(--accent-lime);
		color: #000;
	}
	.badge.cx {
		background: var(--accent-hot);
		color: #000;
	}
	.badge.sid {
		background: var(--accent-cyan);
		color: #000;
	}

	/* Pixel-art bot avatar drawn with CSS box-shadow */
	.avatar {
		flex-shrink: 0;
	}
	.pixel-bot {
		width: 64px;
		height: 64px;
		position: relative;
		image-rendering: pixelated;
	}
	.pixel-bot .row {
		display: block;
		height: 8px;
		width: 64px;
		background-size: 8px 8px;
		background-repeat: no-repeat;
	}
	/* Crude 8x8 pixel face built from gradients */
	.r1 { background:
		linear-gradient(to right, transparent 16px, #000 16px 48px, transparent 48px); }
	.r2 { background:
		linear-gradient(to right, transparent 8px, #000 8px 16px, var(--accent-cyan) 16px 48px, #000 48px 56px, transparent 56px); }
	.r3 { background:
		linear-gradient(to right, #000 0 8px, var(--accent-cyan) 8px 16px, #fff 16px 24px, var(--accent-cyan) 24px 40px, #fff 40px 48px, var(--accent-cyan) 48px 56px, #000 56px 64px); }
	.r4 { background:
		linear-gradient(to right, #000 0 8px, var(--accent-cyan) 8px 16px, #000 16px 24px, var(--accent-cyan) 24px 40px, #000 40px 48px, var(--accent-cyan) 48px 56px, #000 56px 64px); }
	.r5 { background:
		linear-gradient(to right, transparent 8px, #000 8px 16px, var(--accent-cyan) 16px 24px, var(--accent-hot) 24px 40px, var(--accent-cyan) 40px 48px, #000 48px 56px, transparent 56px); }
	.r6 { background:
		linear-gradient(to right, transparent 16px, #000 16px 48px, transparent 48px); }

	.messages {
		flex: 1;
		overflow-y: auto;
		display: flex;
		flex-direction: column;
		gap: 1rem;
		padding: 1rem;
		background: var(--bg-card);
		border: 4px solid #000;
		box-shadow: inset 0 0 0 2px var(--bg-panel);
	}
	.messages::-webkit-scrollbar { width: 14px; }
	.messages::-webkit-scrollbar-track { background: var(--bg-panel); border-left: 2px solid #000; }
	.messages::-webkit-scrollbar-thumb { background: var(--accent); border: 2px solid #000; }

	.placeholder {
		text-align: center;
		padding: 3rem 1rem;
	}
	.placeholder-title {
		font-family: 'Press Start 2P', monospace;
		font-size: 1rem;
		color: var(--accent);
		text-shadow: 2px 2px 0 #000;
		margin: 0 0 0.75rem 0;
		animation: blink 1.2s steps(2, end) infinite;
	}
	.placeholder-sub {
		color: var(--text-muted);
		font-size: 1.05rem;
		margin: 0 0 1.5rem 0;
	}
	@keyframes blink {
		50% { opacity: 0.3; }
	}

	.topic-grid {
		display: flex;
		justify-content: center;
		gap: 0.75rem;
		flex-wrap: wrap;
		padding: 0.6rem 0.75rem;
		background: var(--bg-card);
		border: 4px solid #000;
		box-shadow: 4px 4px 0 #000;
	}
	.topic {
		display: flex;
		flex-direction: row;
		align-items: center;
		gap: 0.6rem;
		padding: 0.5rem 0.8rem;
		background: var(--bg-panel);
		border: 3px solid #000;
		box-shadow: 3px 3px 0 #000;
		cursor: pointer;
		font-family: 'Press Start 2P', monospace;
		transition: transform 0.05s, box-shadow 0.05s, background 0.1s;
	}
	.topic:hover:not(:disabled) {
		background: var(--accent);
		transform: translate(-1px, -1px);
		box-shadow: 4px 4px 0 #000;
	}
	.topic:active:not(:disabled) {
		transform: translate(2px, 2px);
		box-shadow: 1px 1px 0 #000;
	}
	.topic:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}
	.sprite {
		width: 32px;
		height: 32px;
		image-rendering: pixelated;
		flex-shrink: 0;
	}
	.topic-label {
		font-size: 0.55rem;
		color: var(--text);
		text-transform: uppercase;
		letter-spacing: 0.08em;
	}
	.topic:hover:not(:disabled) .topic-label {
		color: #000;
	}
	.topic.tilt:hover:not(:disabled) {
		background: #ff3838;
	}

	.message {
		padding: 0.85rem 1rem;
		background: var(--bg-panel);
		border: 3px solid #000;
		box-shadow: 4px 4px 0 #000;
		max-width: 85%;
		font-size: 1.05rem;
		line-height: 1.45;
	}
	.message.user {
		align-self: flex-end;
		background: var(--accent);
		color: var(--bg-dark);
	}
	.message.assistant {
		align-self: flex-start;
		background: var(--accent-cyan);
		color: var(--bg-dark);
	}
	.message.assistant.loading {
		background: var(--bg-panel);
		color: var(--text);
	}
	.message .role {
		display: block;
		font-family: 'Press Start 2P', monospace;
		font-size: 0.5rem;
		text-transform: uppercase;
		margin-bottom: 0.5rem;
		color: #000;
		letter-spacing: 0.05em;
	}
	.message.assistant.loading .role {
		color: var(--accent-hot);
	}
	.message p {
		margin: 0;
		white-space: pre-wrap;
	}

	.dots span { animation: bob 1s infinite; display: inline-block; }
	.dots span:nth-child(2) { animation-delay: 0.15s; }
	.dots span:nth-child(3) { animation-delay: 0.3s; }
	@keyframes bob {
		0%, 100% { transform: translateY(0); }
		50% { transform: translateY(-4px); }
	}

	.thinking-elapsed {
		margin-left: 0.35rem;
		font-variant-numeric: tabular-nums;
		color: var(--accent);
		font-family: 'Press Start 2P', monospace;
		font-size: 0.65rem;
	}

	form {
		display: flex;
		gap: 0.75rem;
		padding: 0.75rem;
		background: var(--bg-card);
		border: 4px solid #000;
		box-shadow: 4px 4px 0 #000;
	}
	input {
		flex: 1;
		padding: 0.75rem 0.9rem;
		background: #000;
		color: var(--accent-lime);
		border: 3px solid var(--accent);
		box-shadow: inset 2px 2px 0 rgba(57, 255, 142, 0.25);
		font-family: 'VT323', monospace;
		font-size: 1.2rem;
		outline: none;
	}
	input::placeholder {
		color: var(--text-muted);
	}
	input:focus {
		border-color: var(--accent-hot);
	}
	input:disabled {
		opacity: 0.6;
		cursor: not-allowed;
	}
	button {
		padding: 0.75rem 1.25rem;
		background: var(--accent);
		color: #000;
		border: 3px solid #000;
		box-shadow: 4px 4px 0 #000;
		font-family: 'Press Start 2P', monospace;
		font-size: 0.7rem;
		text-transform: uppercase;
		cursor: pointer;
		transition: transform 0.05s, box-shadow 0.05s;
	}
	button:hover:not(:disabled) {
		background: var(--accent-hot);
		color: #000;
	}
	button:active:not(:disabled) {
		transform: translate(2px, 2px);
		box-shadow: 2px 2px 0 #000;
	}
	button:disabled {
		opacity: 0.5;
		cursor: not-allowed;
		background: var(--text-muted);
	}
	button.new-session {
		background: var(--accent-orange);
		color: #000;
	}
	button.new-session:hover:not(:disabled) {
		background: var(--accent-lime);
		color: #000;
	}
</style>
