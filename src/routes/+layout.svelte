<script lang="ts">
	import { onMount } from 'svelte';
	import favicon from '$lib/assets/favicon.svg';
	import { initCoralogixRum } from '$lib/coralogix-rum';
	import '$lib/app.css';

	let { children, data } = $props();

	onMount(() => {
		const rumKey = data.rumPublicKey || import.meta.env.VITE_CORALOGIX_RUM_KEY;
		const rumDomain = data.rumCoralogixDomain;
		void initCoralogixRum(rumKey ?? '', rumDomain).catch((err: unknown) => {
			console.error('[Coralogix RUM] init failed', rumDomain, err);
		});
	});
</script>

<style>
	.app-shell {
		height: 100vh;
		display: flex;
		flex-direction: column;
		overflow: hidden;
	}
	.app-main {
		flex: 1;
		min-height: 0;
		display: flex;
		flex-direction: column;
		overflow: hidden;
	}
	.app-nav {
		flex-shrink: 0;
		display: flex;
		gap: 0.75rem;
		align-items: center;
		padding: 0.75rem 1.25rem;
		background: var(--bg-card);
		border-bottom: 4px solid #000;
		box-shadow: 0 4px 0 var(--accent);
		font-family: 'Press Start 2P', monospace;
		font-size: 0.65rem;
		text-transform: uppercase;
	}
	.app-nav .brand {
		color: var(--accent);
		margin-right: 0.5rem;
		text-shadow: 2px 2px 0 #000;
		letter-spacing: 0.05em;
	}
	.app-nav .brand .pixel {
		color: var(--accent-hot);
	}
	.app-nav a {
		color: var(--text);
		text-decoration: none;
		padding: 0.5rem 0.75rem;
		background: var(--bg-panel);
		border: 3px solid #000;
		box-shadow: 3px 3px 0 #000;
		transition: transform 0.05s, box-shadow 0.05s;
	}
	.app-nav a:hover {
		color: var(--bg-dark);
		background: var(--accent);
	}
	.app-nav a:active {
		transform: translate(2px, 2px);
		box-shadow: 1px 1px 0 #000;
	}
</style>

<svelte:head>
	<title>Coralogix Arcade — AI Center Demo</title>
	<link rel="icon" href={favicon} />
</svelte:head>

<div class="app-shell">
	<nav class="app-nav">
		<span class="brand">CoraBot<span class="pixel">.AI</span></span>
		<a href="/">Chat</a>
		<a href="/source">Source</a>
	</nav>
	<div class="app-main">
		{@render children()}
	</div>
</div>
