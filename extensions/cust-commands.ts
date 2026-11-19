/**
 * Custom commands.
 *
 * /delete — remove the current session file. Pi refuses to delete the active
 * session from /resume, so switch to a fresh session first, then unlink the old
 * file: while the old session is active the process still writes to it.
 *
 * /exit — alias of the built-in /quit. Both go through Pi's graceful shutdown
 * path (same as Ctrl+D): immediate when idle, deferred until the current run
 * settles otherwise.
 */
import { stat, unlink } from "node:fs/promises";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
	pi.registerCommand("delete", {
		description: "Delete the current session and start a new one",
		handler: async (_args, ctx) => {
			const file = ctx.sessionManager.getSessionFile();
			if (!file) {
				ctx.ui.notify("Ephemeral session (--no-session), nothing to delete", "info");
				return;
			}
			try {
				await stat(file);
			} catch {
				ctx.ui.notify("Session not yet saved to disk, nothing to delete", "info");
				return;
			}
			if (!(await ctx.ui.confirm("Delete current session?", file))) return;
			await ctx.newSession({
				withSession: async (fresh) => {
					await unlink(file);
					fresh.ui.notify(`Deleted session ${file}`, "info");
				},
			});
		},
	});

	pi.registerCommand("exit", {
		description: "Quit pi",
		handler: (_args, ctx) => {
			ctx.shutdown();
		},
	});
}