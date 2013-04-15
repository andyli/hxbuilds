import sys.db.Manager;
import sys.db.TableCreate;
import sys.FileSystem;
import haxe.io.Path;
import db.TestContact;
import db.TestResult;
import db.Test;
import db.Revision;
import sys.io.Process;
class Runner
{
	function new()
	{
	}

	static var cmds:Map<String, {description:String, args:String, func:Array<String>->Void}> = [
		"run" => {
			description: "runs an executable as part of a unit test",
			args:"<project> <rev> <test> <target> <executable> [arg1,arg2,...argN]",
			func:function(args:Array<String>)
			{
				if (args.length < 5)
				{
					usage();
					Sys.exit(1);
				}

				var project = args.shift(), rev = args.shift(), test = args.shift(), target = args.shift(), cmd = args.shift();
				run(project,rev,test,target,cmd,args);
			}
		},
		"run-project" => {
			description: "runs all unit tests that follow the structure <project>/installed-tests/<test>/targets/<target>/exec",
			args:"<project-home> <project> <rev>",
			func:function(args:Array<String>)
			{
				if (args.length != 3)
				{
					usage();
					Sys.exit(1);
				}

				runProject(args[0], args[1], args[2]);
			}
		},
		"create-db" => {
			description: "creates the database tables",
			args:"",
			func:function(args:Array<String>)
			{
				TableCreate.create(Revision.manager);
				Manager.cnx.request('CREATE UNIQUE INDEX project_rev ON Revision (project,revision)');
				Manager.cnx.request('CREATE INDEX rdate_project ON Revision (firstRun,project)');
				TableCreate.create(TestResult.manager);
				Manager.cnx.request('CREATE UNIQUE INDEX rev_test_target ON TestResult (revision_id,test_id,target)');
				TableCreate.create(Test.manager);
				Manager.cnx.request('CREATE UNIQUE INDEX project_name ON Test (project,name)');
				TableCreate.create(TestContact.manager);
			}
		},
		"addrev" => {
			description: "creates or modifies a revision",
			args:"<project> <revision> [author] [message] [date]",
			func:function(args:Array<String>)
			{
				if (args.length < 3)
				{
					usage();
					Sys.exit(1);
				}
				var project = args[0], revision = args[1], author = args[2], message = args[3], date = args[4];
				var rev:Revision = Revision.manager.select($project == project && $revision == revision,null,true);
				if (rev == null)
				{
					rev = new Revision();
					rev.project = project;
					rev.revision = revision;
					rev.firstRun = Date.now();
					rev.insert();
				}

				if (author != null)
				{
					rev.author = author;
				}

				if (message != null)
				{
					rev.log = message;
				}

				if (date != null)
				{
					rev.date = Date.fromString(date);
				}
				rev.update();
			}
		},
		"addcontact" => {
			description: "Adds a contact",
			args:"<project> <name> <email> [test-name]",
			func:function(args:Array<String>)
			{
				if (args.length < 3)
				{
					usage(); Sys.exit(1);
				}

				var project = args[0], name = args[1], email = args[2], tname = args[3];
				var c = new TestContact();
				c.project = project;
				c.name = name;
				c.email = email;
				c.testName = name;
				c.insert();
			}
		},
		"rmcontact" => {
			description: "Removes a contact by email",
			args:"<email>",
			func:function(args:Array<String>)
			{
				if (args.length != 1)
				{
					usage(); Sys.exit(1);
				}

				Manager.cnx.request("DELETE FROM TestContact WHERE email = " + Manager.quoteAny(args[0]));
			}
		},
	];

	static function usage()
	{
		Sys.println("Usage: neko runner <command> [command-arguments]");
		Sys.println("command can be:");
		for( k in cmds.keys() )
		{
			var c = cmds.get(k);
			Sys.println('\t$k ${c.args} : ${c.description}');
		}
	}

	static function runProject(projectLocation:String, project:String, rev:String)
	{
		if (!FileSystem.exists(projectLocation + "/installed-tests"))
		{
			Sys.println("No tests to execute");
			Sys.exit(0);
		}

		for (test in FileSystem.readDirectory(projectLocation + "/installed-tests"))
		{
			var path = projectLocation + "/installed-tests/" + test;
			var t:Test = Test.manager.select($project == project && $name == test, null, true);
			if (!FileSystem.exists(path + "/targets"))
			{
				Sys.println("$test: no target to run");
			} else {
				for(target in FileSystem.readDirectory(path + "/targets"))
				{
					var path = path + "/targets/" + target;
					run(project, rev, test, target, path + "/exec", []);
				}
			}
		}
	}

	static function run(project:String,rev:String,test:String,target:String,cmd:String,args:Array<String>):Void
	{
		var t:Test = Test.manager.select($project == project && $name == test,null,false);
		if (t == null)
		{
			t = new Test();
			t.project = project;
			t.name = test;
			t.category = "defaullt";
			t.inUse = true;
			t.insert();
		}

		var r:Revision = Revision.manager.select($project == project && $revision == rev,null,false);
		if (r == null)
		{
			r = new Revision();
			r.project = project;
			r.revision = rev;
			r.firstRun = Date.now();
			r.insert();
		}

		var process = new Process(cmd, args);
		var out = process.stdout.readAll().toString();
		var err = process.stderr.readAll().toString();
		var exit = process.exitCode();

		if (exit != 0)
		{
			var lastr = TestResult.manager.select($test == t, {orderBy:[-dateRan], limit:1}, false);
			if (lastr == null || lastr.success) //don't flood
			{
				for (contact in TestContact.manager.search( ($project == t.project) && ($testName == null || $testName == t.name) ))
				{
					var pr = new Process("mail", ["-s", '[test-runner] "$project $test" failed @ $rev [$target]', contact.email]);
					var name = contact.name;
					pr.stdin.writeString('$name,\nThe Test "$project $test" has failed with exit code $exit while running for revision $rev ($target)\n\tstdout:\n$out\n\tsterr:\n$err');
					pr.exitCode();
				}
			}
		}

		var result:TestResult = new TestResult();
		result.dateRan = Date.now();
		result.exitCode = exit;
		result.success = (exit == 0);
		result.target = target;
		result.stderr = err;
		result.stdout = out;
		result.revision = r;
		result.test = t;
		result.insert();
	}

	static function main()
	{
		var args = Sys.args();
		if (args.length < 1)
		{
			usage();
			Sys.exit(1);
		}

		Env.init();
		Manager.initialize();

		var arg = args.shift();
		var cmd = cmds.get(arg);
		if (cmd == null)
		{
			print("Unrecognized command: " + arg);
			Sys.exit(1);
		}

		cmd.func(args);
	}

	private static function print(v:Dynamic)
	{
		Sys.println(Std.string(v));
	}
}
