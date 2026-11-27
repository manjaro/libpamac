/*
 *  pamac-vala
 *
 *  Copyright (C) 2026 Guillaume Benoit <guillaume@manjaro.org>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

// helpers shared by the test programs
namespace Pamac {
	// records the progress it receives, from any thread
	internal class RecordingSink : Object, TransactionSink {
		string name;
		Mutex mutex;
		GenericArray<string> events;

		public RecordingSink (string name) {
			this.name = name;
			mutex = Mutex ();
			events = new GenericArray<string> ();
		}

		// an event is "kind: text", e.g. "action: Synchronizing package databases..."
		void record (string kind, string text = "") {
			string event = text == "" ? kind : "%s: %s".printf (kind, text);
			mutex.lock ();
			events.add (event);
			mutex.unlock ();
			if (GLib.Test.verbose ()) {
				GLib.Test.message ("[%s] %s", name, event);
			}
		}

		// number of the events of this kind whose text contains text
		public uint count (string kind, string text = "") {
			uint n = 0;
			mutex.lock ();
			foreach (unowned string event in events) {
				if (event.has_prefix (kind) && text in event) {
					n++;
				}
			}
			mutex.unlock ();
			return n;
		}

		public bool has (string kind, string text = "") {
			return count (kind, text) > 0;
		}

		// write all the events in the test log
		public void dump () {
			mutex.lock ();
			foreach (unowned string event in events) {
				GLib.Test.message ("[%s] %s", name, event);
			}
			mutex.unlock ();
		}

		public void emit_action (string action) {
			record ("action", action);
		}

		public void emit_action_progress (string action, string status, double progress) {
			record ("action_progress", action);
		}

		public void emit_download_progress (string action, string status, double progress) {
			record ("download_progress", action);
		}

		public void emit_hook_progress (string action, string details, string status, double progress) {
			record ("hook_progress", details);
		}

		public void emit_script_output (string message) {
			record ("script_output", message);
		}

		public void emit_warning (string message) {
			record ("warning", message);
		}

		public void emit_error (string message, GenericArray<string> details) {
			record ("error", "%s %s".printf (message, string.joinv (" ", details.data)));
		}

		public void important_details_outpout (bool must_show) {
			record ("important_details", must_show.to_string ());
		}

		public void start_downloading () {
			record ("start_downloading");
		}

		public void stop_downloading () {
			record ("stop_downloading");
		}

		public void start_waiting () {
			record ("start_waiting");
		}

		public void stop_waiting () {
			record ("stop_waiting");
		}

		public int choose_provider (string depend, GenericArray<string> providers) {
			record ("choose_provider", depend);
			return 0;
		}
	}

	// run a test coroutine in a main loop, a thrown error fails the test:
	// run_async_test ((cb) => test.begin (cb), (res) => test.end (res))
	delegate void AsyncTestBegin (AsyncReadyCallback callback);
	delegate void AsyncTestEnd (AsyncResult res) throws Error;

	void run_async_test (AsyncTestBegin begin, AsyncTestEnd end) {
		var loop = new MainLoop ();
		begin ((obj, res) => {
			try {
				end (res);
			} catch (Error e) {
				error (e.message);
			}
			loop.quit ();
		});
		loop.run ();
	}

	// fail the test if an operation failed, with the progress it reported:
	// the reason of the failure is in it
	void assert_operation (bool success, RecordingSink sink, string operation) {
		if (!success) {
			sink.dump ();
			error ("%s failed, see the events above", operation);
		}
	}

	async void wait_ms (uint ms) {
		var timeout = new TimeoutSource (ms);
		timeout.set_callback (wait_ms.callback);
		timeout.attach (MainContext.default ());
		yield;
	}

	// wait until condition is true, at most timeout_ms: returns the last value of condition
	delegate bool Condition ();

	async bool wait_for (owned Condition condition, uint timeout_ms) {
		int64 deadline = get_monotonic_time () + timeout_ms * TimeSpan.MILLISECOND;
		while (!condition ()) {
			if (get_monotonic_time () >= deadline) {
				return false;
			}
			yield wait_ms (20);
		}
		return true;
	}

	double seconds_since (int64 start) {
		return (double) (get_monotonic_time () - start) / TimeSpan.SECOND;
	}

	// GLib.Test makes the warnings fatal: the tested code logs some on purpose
	void init_tests (ref unowned string[] args) {
		GLib.Test.init (ref args);
		Log.set_always_fatal (LogLevelFlags.LEVEL_ERROR | LogLevelFlags.LEVEL_CRITICAL);
	}

	// exit status of a test program which can not run here, see meson test
	const int SKIP = 77;
}
