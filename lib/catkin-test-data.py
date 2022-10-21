#!/usr/bin/env python3


import sys
import re
import os
import glob
import json
from urllib.parse import urlparse

# https://github.com/ros/catkin/tree/0.8.9
# https://github.com/ros/catkin/blob/0.8.9/cmake/test/catkin_download_test_data.cmake#L37
# catkin_download_test_data target url
#
# Test data adds EXCLUDE_FROM_ALL and hands it off to catkin_download which takes:
#
# :param target: the target name
# :type target: string
# :param url: the url to download
# :type url: string
#
# :param DESTINATION: the directory where the file is downloaded to
#   (default: ${PROJECT_BINARY_DIR})
# :type DESTINATION: string
# :param FILENAME: the filename of the downloaded file
#   (default: the basename of the url)
# :type FILENAME: string
# :param MD5: the expected md5 hash to compare against
#   (default: empty, skipping the check)
# :type MD5: string
#
# Additionally, options EXCLUDE_FROM_ALL and REQUIRED can be specified.

# Some examples to test with.
test_cases = [
    ( # Multiline comment.
        """
          # catkin_download_test_data(
          #   frame.bag
          #   https://dev-vm-webviz-01.clearpath.ai/nas/rostest/visual_odometry/frame.bag
          #   DESTINATION ${PROJECT_SOURCE_DIR}/test
          #   MD5 d3c99ea641acb49593e2a3c9890b2086
          # )
        """,
        [] # Expected no matches.
    ),
    (
        """
        catkin_download_test_data(download_data_test_constants_gen1.bag http://download.ros.org/data/test_rosbag/constants_gen1.bag FILENAME test/constants_gen1.bag MD5 77ec8cb20e823ee3f3a87d07ea1132df )
        """,
        [{"name":"test/constants_gen1.bag", # Directory wouldn't exist, sanitization makes it into _
          "name_valid": "test/constants_gen1.bag".replace("/", "_"),
          "url":"http://download.ros.org/data/test_rosbag/constants_gen1.bag",
          "outputHash":"77ec8cb20e823ee3f3a87d07ea1132df"}]
    ),
    ( # Single line comment
        """
        #catkin_download_test_data(download_data_test_constants_gen1.bag http://download.ros.org/data/test_rosbag/constants_gen1.bag FILENAME test/constants_gen1.bag MD5 77ec8cb20e823ee3f3a87d07ea1132df )
        """,
        []
    ),
    ( # Url with get parameters.
        """
          catkin_download_test_data(
            joint_states_indexed_bag
            http://wiki.ros.org/robot_state_publisher/data?action=AttachFile&do=get&target=joint_states_indexed.bag
            DESTINATION ${CATKIN_DEVEL_PREFIX}/${CATKIN_PACKAGE_SHARE_DESTINATION}/test
            FILENAME joint_states_indexed.bag
            MD5 793e0b566ebe4698265a936b92fa2bba)
        """,
        [{"name":"joint_states_indexed.bag",
          "name_valid": "joint_states_indexed.bag",
          "url":"http://wiki.ros.org/robot_state_publisher/data?action=AttachFile&do=get&target=joint_states_indexed.bag",
          "outputHash":"793e0b566ebe4698265a936b92fa2bba"}],
    ),
    ( # comment in center.
        """
           catkin_download_test_data(
             frame.bag
             # https://dev-vm-webviz-01.clearpath.ai/nas/rostest/visual_odometry/frame.bag
             https://dev-vm-webviz-01.clearpath.ai/nas/rostest/visual_odometry/foobarbuz.bag
             DESTINATION ${PROJECT_SOURCE_DIR}/test
             MD5 d3c99ea641acb49593e2a3c9890b2086
           )
        """,
        [{"name":"foobarbuz.bag",
          "name_valid": "foobarbuz.bag",
          "url":"https://dev-vm-webviz-01.clearpath.ai/nas/rostest/visual_odometry/foobarbuz.bag",
          "outputHash":"d3c99ea641acb49593e2a3c9890b2086"}]
    ),
]

def find_cmake_lists(dir):
    return glob.glob(os.path.join(dir, '**', 'CMakeLists.txt'), recursive=True)

def parse_cmakelist_for_downloads(cmake_file_content):
    def sanitize(path):
        # Only allow trivial ascii names without subpaths. that fetchUrl will allow
        return re.sub('[^a-zA-Z0-9.]', '_', path)

    def try_to_make_up_name(url):
        entry = urlparse(url)
        best_guess = os.path.basename(entry.path)
        if not "." in best_guess: # No extension, something went bad. 
            return None
        return best_guess

    urls_to_download = []

    # Strip all commented out lines.
    cmake_file_content = "\n".join([l for l in cmake_file_content.split("\n") if not l.strip().startswith("#")])

    # First, find all catkin_download_test_data sections.
    parsed_entries = re.findall("catkin_download_test_data\(([^)]+?)\)", cmake_file_content, flags=re.DOTALL)

    # Next, we have the to parse the actual entries we have now obtained.
    for entry in parsed_entries:
        args = entry.split()
        url = args[1]
        entry_dict = {"url":url, "outputHash":None}

        # Anything beyond args[1] is pairs of (KEY value)
        for i in range(int((len(args) - 2) / 2)):
            key = args[i * 2 + 2]
            value = args[i * 2 + 3]
            if key == "MD5":
                entry_dict["outputHash"] = value
            if key == "FILENAME":
                entry_dict["name"] = value

        if entry_dict["outputHash"] is None:
            raise BaseException(f"No md5 sum found for {url}, aborting.")

        if not "name" in entry_dict:
            guess = try_to_make_up_name(url)
            if guess is not None:
                entry_dict["name"] = guess

        if "name" in entry_dict:
            entry_dict["name_valid"] = sanitize(entry_dict["name"])

        urls_to_download.append(entry_dict)

    return urls_to_download

def parse_cmakelists(directory):
    collected = []
    cmakelist_files = find_cmake_lists(directory)
    for file_path in cmakelist_files:
        with open(file_path) as f:
            cmake_file = f.read()
        collected.extend(parse_cmakelist_for_downloads(cmake_file))
    return collected


def dict_to_nix_set(d):
    t = "{"
    for k, v in sorted(d.items()):
        t += str(k)
        t += " = "
        t += json.dumps(v)
        t += ";\n"
    t += "}"
    return t


def create_nix_file(url_md5s):
    return "[\n" + "".join('    {}\n'.format(dict_to_nix_set(v)) for v in url_md5s) + "]\n"

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Missing output argument, running in test mode.")
        if len(sys.argv) < 2:
            print("No input specified, running tests")
            for text, expected in test_cases:
                result = parse_cmakelist_for_downloads(text)
                print()
                print(f"Text was:\n{text}")
                print(f"Result    {result}")
                print(f"Expected  {expected}")
                assert len(expected) == len(result)
                for found_dl, expected_dl in zip(result, expected):
                    for key in (set(found_dl.keys()) | set(expected_dl)):
                        assert found_dl[key] == expected_dl[key]
            sys.exit(0)
        input_dir = sys.argv[1]
        res = parse_cmakelists(input_dir)
        print(res)
        print(create_nix_file(res))
        sys.exit(1)

    input_dir = sys.argv[1]
    res = parse_cmakelists(input_dir)
    output_dir = sys.argv[2]
    with open(os.path.join(output_dir, "default.nix"), "w") as f:
        f.write(create_nix_file(res))

