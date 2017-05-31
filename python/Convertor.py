# -*- coding: utf-8 -*-
"""
Convertor - From points and lines to faces

"""

import sys
from shapely.geometry import MultiLineString
from shapely.geometry import MultiPolygon
from shapely.ops import polygonize_full
from shapely.ops import cascaded_union

# Open file stream
if len(sys.argv) is 1:
    fin = open('geometry.geo', 'r')
    filename = 'geometry'
    filetype = 'geo'
if len(sys.argv) is 2:
    fin = open(sys.argv[1], 'r')
    filename, filetype = sys.argv[1].split('.')

print '\nFilename: ', filename, '\nFiletype: ', filetype, '\n'

# ==================================================
# Read GEO data
# ==================================================
if filetype == 'geo':
    str = fin.readline()
    str = str.split("\t")

    n_point = int(str[0])
    n_line  = int(str[1])
    n_face  = int(str[2])

    # ==================================================
    # Read points
    # ==================================================
    points = []
    for i in range(n_point):
        str = fin.readline()
        point = str.split()
        points.append([float(point[1]), -float(point[2])])

    # Print points
    print 'Points: ', n_point
    for i in range(n_point):
        print i+1, ' th points : ', points[i]
    print '\n'

    # ==================================================
    # Read lines
    # ==================================================
    lines = []
    for i in range(n_line):
        str = fin.readline()
        line = str.split()
        lines.append([int(line[1]), int(line[2])])
        
    # Print lines
    print 'Lines:',  n_line
    for i in range(n_line):
        print i+1, ' th lines : ', lines[i]
    print '\n'
    
    # ==================================================
    # Make lines with points
    # ==================================================
    linepoints = []
    for i in range(n_line):
        poi1, poi2 = lines[i]
        linepoint = [((points[poi1-1]),(points[poi2-1]))]
        linepoints.extend(linepoint)

# ==================================================
# Read IGES data
# ==================================================
if filetype == 'iges':

    linepoints = []
    while True:
        str = fin.readline()
        if str == '':
            break
        str = str.split(',')

        # Add lines
        points = []
        if str[0] == '110':
            index = len(str) - 2
            for i in (range(1,len(str)-1)):
                points.append(float(str[i]))
                #print points
            else:
                if index is 3:
                    #print "333"
                    str = fin.readline()
                    str = str.split(',')
                    split0 = str[2].split(';')
                    #print str[0], str[1], split0[0]
                    points.append(float(str[0]))
                    points.append(float(str[1]))
                    points.append(float(split0[0]))
                if index is 4:
                    #print "444"
                    str = fin.readline()
                    str = str.split(',')
                    split0 = str[1].split(';')
                    #print str[0], split0[0]
                    points.append(float(str[0]))
                    points.append(float(split0[0]))
                if index is 5:
                    #print "555"
                    str = fin.readline()
                    str = str.split(';')
                    #print str[0]
                    points.append(float(str[0]))
                 
            linepoint = [((points[0], points[1]), (points[3], points[4]))]
            print linepoint
            linepoints.extend(linepoint)
        
    n_line = len(linepoints)
    print n_line

fin.close()
#sys.exit()

# Print line list with points
print 'Lines with points: ', n_line
for i in range(n_line):
    print i+1, ' th lines with points : ', linepoints[i]
print '\n'

# ==================================================
# Make mutilinestring from line list
# ==================================================
multilines = MultiLineString(linepoints)

x = multilines.intersection(multilines)

# Polygonize
result, dangles, cuts, invalids = polygonize_full(x)

result = MultiPolygon(result)
polygon = cascaded_union(result)

# Make mutilinestring from line list
#multilines = MultiLineString(linepoints)

# Polygonize
#result, dangles, cuts, invalids = polygonize_full(multilines)

#result = MultiPolygon(result)
#polygon = cascaded_union(result)

##################################################
multilines = polygon.boundary.union(result.boundary)

# Polygonize
result, dangles, cuts, invalids = polygonize_full(multilines)
##################################################

polygon = MultiPolygon(result)

# Print polygon
print 'Polygons: ', len(polygon)
for i in range(len(polygon)):
    print i+1, ' th', polygon[i]
print '\n'

# ==================================================
# Extract points
# ==================================================
points = []
for i in range(len(polygon)):
    point = list(polygon[i].exterior.coords)
    for j in range(len(point)):
        x = point[j]
        if x not in points:
            points.extend([(x[0], x[1])])

# Print points
print 'Points: ', len(points)
for i in range(len(points)):
    print i+1, ' th point : ', points[i]
print '\n'

# ==================================================
# Face connectivity
# ==================================================
conns = []
for i in range(len(polygon)):
    conn  = polygon[i].exterior.coords
    count = len(polygon[i].exterior.coords)
    face  = []
    for j in range(count-1):
        face.append(points.index(conn[j]))

    # Make connectivity
    conns.append(face)

# Print connectivity
print 'Face connectivity: ', len(conns)
for i in range(len(conns)):
    print i+1, ' th connectivity : ', len(conns[i]), ' - ', conns[i]
print '\n'

# ==================================================
# Write file
# ==================================================
# Open file stream
if len(sys.argv) is 1:
    str = 'geometry.tmp'
    
if len(sys.argv) is 2:
    str = sys.argv[1]

filename, filetype = str.split('.')
fout = open(filename+'.tmp', 'w')

fout.write('%d\t' % len(points))
fout.write('0\t')
fout.write('%d\n' % len(conns))
for i in range(len(points)):
    fout.write('%d \t' % (i+1))
    fout.write('%s \t %s \t\n' % points[i])

for i in range(len(conns)):
    fout.write('%d \t' % (i+1))
    fout.write('%d \t' % len(conns[i]))
    for j in range(len(conns[i])-1, -1, -1):
        entity = conns[i][j] + 1
        fout.write('%d \t' %entity)
    
    fout.write('\n')
fout.close()