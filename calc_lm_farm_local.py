import argparse
import multiprocessing
import subprocess
import os
import datetime

parser = argparse.ArgumentParser()
parser.add_argument("scenario",help="scenario tag path")
parser.add_argument("bsp_name",help="bsp name")
parser.add_argument("quality",help="light quality", choices=['high', 'medium', 'low', 'direct_only', 'super_slow', 'draft', 'debug'])
parser.add_argument("light_group",help="light group", nargs='?', const=1, default="all")
args = parser.parse_args()

blob_dir_name = "111"
blob_dir = "faux\\" + blob_dir_name
tool_name = "tool_fast"

begin_time = datetime.datetime.now()

def print_with_exec_time(text):
   exec_time = datetime.datetime.now() - begin_time
   print("*** " + text + " *** (" + str(exec_time) + ")")

def launch_client(stage, client_index, client_number):
   log_filename = blob_dir + "\\logs\\" + stage + str(client_index) + ".txt"
   log_dir = os.path.dirname(log_filename)
   if not os.path.exists(log_dir):
      os.makedirs(log_dir)
   log = open(log_filename, 'w')
   return subprocess.Popen([tool_name, "faux_farm_" + stage, blob_dir, str(client_index), str(client_number)],
      stdout=log, stderr=log), log_filename

def launch_farm(stage, client_number):
   print_with_exec_time("farm stage: " + stage)
   procs = [launch_client(stage, client_index, client_number) for client_index in range(client_number)]
   for p, log_filename in procs:
      if p.wait() != 0:
         print("Client tool execution failed, see log for details: " + log_filename)
         raise RuntimeError("Client error code: " + str(p.returncode))
   subprocess.check_call([tool_name, "faux_farm_" + stage + "_merge", blob_dir, str(client_number)])

# -----------------------------------------------------------------------------

print_with_exec_time("faux_data_sync")
subprocess.check_call([tool_name, "faux_data_sync", args.scenario, args.bsp_name])

print_with_exec_time("faux_farm_begin")
subprocess.check_call([tool_name, "faux_farm_begin", args.scenario, args.bsp_name, args.light_group, args.quality, blob_dir_name])

client_number = multiprocessing.cpu_count()

launch_farm("dillum", client_number)
launch_farm("pcast", client_number)
launch_farm("radest", client_number)
launch_farm("extillum", client_number)
launch_farm("fgather", client_number)

print_with_exec_time("faux_farm_finish")
subprocess.check_call([tool_name, "faux_farm_finish", blob_dir])


subprocess.check_call([tool_name, "faux-build-linear-textures-with-intensity-from-quadratic", args.scenario, args.bsp_name])
subprocess.check_call([tool_name, "faux-compress-scenario-bitmaps-dxt5", args.scenario, args.bsp_name])
subprocess.check_call([tool_name, "faux-farm-compression-merge", args.scenario, args.bsp_name])

print_with_exec_time("finished")
