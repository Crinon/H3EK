import os
import sys

working_directory = sys.path[0]
reports_path = ""
public_tags_path = 'bin\\!public_tags.txt'

if len(sys.argv) == 3:
	reports_path = sys.argv[1]
	public_tags_path = sys.argv[2]

allset = set()
unreferenced_set = set()
reports_path = reports_path + "reports\\"

def process_directory(directory):
	tag_directory = os.path.join(working_directory, 'tags')
	digsite_directory = os.path.join(tag_directory, directory)
	if os.path.exists(digsite_directory):
		for path, subdirs, files in os.walk(digsite_directory):
			for name in files:
				absolute_file_path = os.path.join(path, name)
				local_path = absolute_file_path.split(tag_directory + os.sep, 1)[1]
				local_path = local_path.lower()
				if not local_path in allset:
					s = local_path.rstrip()
					unreferenced_set.add(s)

def process_file(fname):
	exclude_list = ['.sound_cache_file_gestalt', '.rasterizer_cache_file_globals', '.cache_file_resource_layout_table', '.cache_file_resource_gestalt']

	with open( reports_path + fname + "\\cache_file_loaded_tags.txt", "r") as file:
		for lineNumber, lineText in enumerate(file):
			skip = False
			for ex in exclude_list:
				if lineText.find(ex) > 0:
					skip = True
					break
			if skip:
				continue

			s = lineText.rstrip()
			s = s.replace('/', '\\')
			if s.startswith('\\'):
				s = s[1:]

			#print s
			allset.add(s)




process_file('005_intro')
process_file('010_jungle')
process_file('020_base')
process_file('030_outskirts')
process_file('040_voi')
process_file('050_floodvoi')
process_file('070_waste')
process_file('100_citadel')
process_file('110_hc')
process_file('120_halo')
process_file('130_epilogue')


process_file('zanzibar')
process_file('construct')
process_file('chill')
process_file('cyberdyne')
process_file('deadlock')
process_file('guardian')
process_file('isolation')
process_file('riverworld')
process_file('salvation')
process_file('shrine')
process_file('snowbound')
process_file('armory')
process_file('bunkerworld')
process_file('chillout')
process_file('descent')
process_file('docks')
process_file('fortress')
process_file('ghosttown')
process_file('lockout')
process_file('midship')
process_file('sandbox')
process_file('sidewinder')
process_file('spacecamp')
process_file('warehouse')
process_file('s3d_edge')
process_file('s3d_waterfall')
process_file('s3d_avalanche')
process_file('s3d_lockout')
process_file('s3d_powerhouse')
process_file('s3d_reactor')
process_file('s3d_sky_bridgenew')
process_file('s3d_turf')

process_file('mainmenu')
process_file('box')                           # levels\test\box\box
process_file('audio')                         # levels\reference\audio\audio
process_file('lighting_reference_materials')  # levels\reference\lighting_reference\lighting_reference_materials


psh_dir = 'shaders'

for filename in os.listdir(working_directory + '\\tags\\' + psh_dir):
	if filename.endswith(".hlsl_include"):
		allset.add(psh_dir + '\\' + filename)

allset.add('levels\\shader_collections.txt')
# Trying to create new shader_skin tags will crash without the render_method_definition
allset.add('shaders\\skin.render_method_definition')
allset.add('shaders\\skin_shared_pixel_shaders.global_pixel_shader')
allset.add('shaders\\skin_shared_vertex_shaders.global_vertex_shader')

# Add .scenario_structure_lighting_info tags
tmp = set()
for s in allset:
	if s.endswith(".scenario_structure_bsp"):
		tmp.add(s[:-3] + "lighting_info")
allset = allset.union(tmp)

# scenarios which are loaded by code during the shared-first and campaign-second commands in BuildOptimizableMapsSimple
process_directory('levels\\shared\\cache')		# tags\levels\shared\cache

with open(public_tags_path, "w") as fout:
	print()
	for s in sorted(allset):
		if os.path.exists(working_directory + '\\tags\\' + s):
			fout.write(s + '\n')

	for s in sorted(unreferenced_set):
		if os.path.exists(working_directory + '\\tags\\' + s):
			fout.write(s + '\n')

print('done')
