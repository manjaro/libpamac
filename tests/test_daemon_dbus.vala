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

// the D-Bus protocol between TransactionInterfaceDaemon and the built pamac-daemon,
// run on a private bus used as the system bus (DBUS_SYSTEM_BUS_ADDRESS).
// There is no polkit on this bus: the operations needing an authorization are refused,
// the tests only use them and the ones which do not touch the system
namespace Pamac {
	const string DAEMON_NAME = "org.manjaro.pamac.daemon";
	const string DAEMON_PATH = "/org/manjaro/pamac/daemon";

	string bus_address;
	Subprocess daemon_process;
	RecordingSink sink;
	TransactionInterfaceDaemon client;

	DBusConnection new_connection () throws Error {
		return new DBusConnection.for_address_sync (bus_address,
													DBusConnectionFlags.AUTHENTICATION_CLIENT |
													DBusConnectionFlags.MESSAGE_BUS_CONNECTION);
	}

	bool daemon_has_owner (DBusConnection connection) {
		try {
			Variant reply = connection.call_sync ("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
												"NameHasOwner", new Variant ("(s)", DAEMON_NAME), new VariantType ("(b)"),
												DBusCallFlags.NONE, -1);
			bool has_owner;
			reply.get ("(b)", out has_owner);
			return has_owner;
		} catch (Error e) {
			return false;
		}
	}

	async void authorization_refused () throws Error {
		uint errors = sink.count ("error", "Authentication failed");
		bool authorized = yield client.get_authorization ();
		assert (!authorized);
		// sent only to this client, see direct_signals_filter
		assert (sink.count ("error", "Authentication failed") > errors);
	}

	void test_authorization_refused () {
		run_async_test ((cb) => authorization_refused.begin (cb), (res) => authorization_refused.end (res));
	}

	// TransactionFinished is broadcast to every client, even after a refused transaction
	async void transaction_finished_broadcast () throws Error {
		var listener = new_connection ();
		bool finished = false;
		uint subscription = listener.signal_subscribe (null, DAEMON_NAME, "TransactionFinished", DAEMON_PATH, null,
														DBusSignalFlags.NONE, () => {
			finished = true;
		});
		var request = new TransactionRequest ();
		request.to_install = {"pamac-test-nothing"};
		bool success = yield client.trans_run (request);
		assert (!success);
		assert (yield wait_for (() => finished, 2000));
		listener.signal_unsubscribe (subscription);
		yield listener.close ();
	}

	void test_transaction_finished_broadcast () {
		run_async_test ((cb) => transaction_finished_broadcast.begin (cb), (res) => transaction_finished_broadcast.end (res));
	}

	// the progress signals of a client are not sent to the others
	async void signals_sent_to_their_client () throws Error {
		var other = new_connection ();
		uint other_errors = 0;
		string? other_recipient = null;
		uint subscription = other.signal_subscribe (null, DAEMON_NAME, "EmitError", DAEMON_PATH, null,
													DBusSignalFlags.NONE, (connection, sender, path, iface, name, parameters) => {
			other_errors++;
			other_recipient = parameters.get_child_value (0).get_string ();
		});
		uint errors = sink.count ("error");
		Variant reply = yield other.call (DAEMON_NAME, DAEMON_PATH, DAEMON_NAME, "GetAuthorization", null,
										new VariantType ("(b)"), DBusCallFlags.NONE, -1);
		bool authorized;
		reply.get ("(b)", out authorized);
		assert (!authorized);
		assert (yield wait_for (() => other_errors > 0, 2000));
		assert (other_recipient == other.get_unique_name ());
		// let a wrongly broadcast signal arrive
		yield wait_ms (200);
		assert (sink.count ("error") == errors);
		other.signal_unsubscribe (subscription);
		yield other.close ();
	}

	void test_signals_sent_to_their_client () {
		run_async_test ((cb) => signals_sent_to_their_client.begin (cb), (res) => signals_sent_to_their_client.end (res));
	}

	void test_cancel_without_operation () {
		try {
			client.trans_cancel ();
		} catch (Error e) {
			error (e.message);
		}
	}

	// the client reports the lost connection and reconnects for the next call
	async void reconnect_after_connection_lost () throws Error {
		uint lost = sink.count ("error", "Connection to the daemon was lost");
		yield Bus.get_sync (BusType.SYSTEM).close ();
		assert (yield wait_for (() => sink.count ("error", "Connection to the daemon was lost") > lost, 2000));
		bool authorized = yield client.get_authorization ();
		assert (!authorized);
	}

	void test_reconnect_after_connection_lost () {
		run_async_test ((cb) => reconnect_after_connection_lost.begin (cb), (res) => reconnect_after_connection_lost.end (res));
	}

	// with no running operation, quit stops the daemon
	async void quit () throws Error {
		client.quit_daemon ();
		bool exited = false;
		daemon_process.wait_async.begin (null, () => {
			exited = true;
		});
		assert (yield wait_for (() => exited, 5000));
	}

	void test_quit () {
		run_async_test ((cb) => quit.begin (cb), (res) => quit.end (res));
	}

	void start_daemon (string daemon_path) throws Error {
		// inherits DBUS_SYSTEM_BUS_ADDRESS
		daemon_process = new Subprocess.newv ({daemon_path}, SubprocessFlags.NONE);
		var connection = new_connection ();
		int64 deadline = get_monotonic_time () + 10 * TimeSpan.SECOND;
		while (!daemon_has_owner (connection)) {
			if (get_monotonic_time () > deadline) {
				throw new IOError.TIMED_OUT ("pamac-daemon did not start");
			}
			Thread.usleep (50000);
		}
		connection.close_sync ();
	}
}

int main (string[] args) {
	Pamac.init_tests (ref args);
	string? daemon_path = Environment.get_variable ("PAMAC_DAEMON");
	if (daemon_path == null) {
		print ("skipped: PAMAC_DAEMON not set, run with meson test\n");
		return Pamac.SKIP;
	}
	if (Environment.find_program_in_path ("dbus-daemon") == null) {
		print ("skipped: dbus-daemon not found\n");
		return Pamac.SKIP;
	}
	var bus = new TestDBus (TestDBusFlags.NONE);
	bus.up ();
	Pamac.bus_address = bus.get_bus_address ();
	// before the first use of the system bus
	Environment.set_variable ("DBUS_SYSTEM_BUS_ADDRESS", Pamac.bus_address, true);
	int status = 1;
	try {
		Pamac.start_daemon (daemon_path);
		Pamac.sink = new Pamac.RecordingSink ("client");
		Pamac.client = new Pamac.TransactionInterfaceDaemon (new Pamac.Config ("/etc/pamac.conf"), Pamac.sink);
		Test.add_func ("/daemon_dbus/authorization_refused", Pamac.test_authorization_refused);
		Test.add_func ("/daemon_dbus/transaction_finished_broadcast", Pamac.test_transaction_finished_broadcast);
		Test.add_func ("/daemon_dbus/signals_sent_to_their_client", Pamac.test_signals_sent_to_their_client);
		Test.add_func ("/daemon_dbus/cancel_without_operation", Pamac.test_cancel_without_operation);
		Test.add_func ("/daemon_dbus/reconnect_after_connection_lost", Pamac.test_reconnect_after_connection_lost);
		Test.add_func ("/daemon_dbus/quit", Pamac.test_quit);
		status = Test.run ();
	} catch (Error e) {
		printerr ("failed to start pamac-daemon: %s\n", e.message);
	}
	if (Pamac.daemon_process != null) {
		Pamac.daemon_process.force_exit ();
	}
	bus.down ();
	return status;
}
