/**
 * Add /exit as an alias of the built-in /quit.
 *
 * Both go through Pi's graceful shutdown path (same as Ctrl+D): immediate when
 * idle, deferred until the current run settles otherwise.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
	pi.registerCommand("exit", {
		description: "Quit pi",
		handler: (_args, ctx) => {
			ctx.shutdown();
		},
	});
}