!
! ---------------------------------------------------------------------------------------
!
!                                   Module for Basepair
!
!                                                            First programed : 2015/04/29
!                                                            Last  modified  : 2017/03/16
!
! Comments: The module is to generate the basepair model.
!
! by Hyungmin Jun (Hyungminjun@outlook.com), MIT, Bathe Lab, 2017
!
! Copyright 2017. Massachusetts Institute of Technology. Rights Reserved.
! M.I.T. hereby makes following copyrightable material available to the
! public under GNU General Public License, version 2 (GPL-2.0). A copy of
! this license is available at https://opensource.org/licenses/GPL-2.0
!
! ---------------------------------------------------------------------------------------
!
module Basepair

    use Data_Prob
    use Data_Geom
    use Data_Bound
    use Data_Mesh

    use Para
    use Mani
    use Math

    use Section

    implicit none

    public  Basepair_Discretize

    private Basepair_Count_Basepair
    private Basepair_Generate_Basepair
    private Basepair_Set_Conn_Junction
    private Basepair_Print_Bound_Data
    private Basepair_Get_Direction_IniL
    private Basepair_Chimera_Cylinder_Ori
    private Basepair_Chimera_Cylinder
    private Basepair_Modify_Junction
    private Basepair_Find_Xover_Nearby
    private Basepair_Increase_Basepair
    private Basepair_Decrease_Basepair
    private Basepair_Make_Ghost_Node
    private Basepair_Increase_Edge
    private Basepair_Add_Basepair
    private Basepair_Delete_Ghost_Node
    private Basepair_Make_Sticky_End
    private Basepair_Chimera_Mesh
    private Basepair_Write_Edge_Length

contains

! ---------------------------------------------------------------------------------------

! Discretize multiple lines to basepairs
! Last updated on Fri 17 Mar 2017 by Hyungmin
subroutine Basepair_Discretize(prob, geom, bound, mesh)
    type(ProbType),  intent(in)    :: prob
    type(GeomType),  intent(inout) :: geom
    type(BoundType), intent(inout) :: bound
    type(MeshType),  intent(inout) :: mesh

    double precision :: i

    ! Print progress
    do i = 0, 11, 11
        write(i, "(a)")
        write(i, "(a)"), "   +--------------------------------------------------------------------+"
        write(i, "(a)"), "   |                                                                    |"
        write(i, "(a)"), "   |                    4. Build the basepair model                     |"
        write(i, "(a)"), "   |                                                                    |"
        write(i, "(a)"), "   +--------------------------------------------------------------------+"
        write(i, "(a)")
    end do

    ! Count the number of basepairs
    call Basepair_Count_Basepair(prob, geom, mesh)

    ! Generate the basepair model
    call Basepair_Generate_Basepair(geom, bound, mesh)

    ! Set sectional connection at the junction
    call Basepair_Set_Conn_Junction(geom, bound, mesh)

    ! Write cylindrial model with orientation
    call Basepair_Chimera_Cylinder_Ori(prob, geom, bound, mesh, "cyl1")

    ! Write cylindrial model, cylinder 1
    call Basepair_Chimera_Cylinder(prob, geom, bound, mesh, "cyl1")

    ! Modify the length of the duplex at the junction
    call Basepair_Modify_Junction(geom, bound, mesh)

    ! Delete ghost node from node data
    call Basepair_Delete_Ghost_Node(geom, bound, mesh)

    ! Add one base to 5'-end
    call Basepair_Make_Sticky_End(geom, bound, mesh)

    ! Write cylindrial model with orientation
    call Basepair_Chimera_Cylinder_Ori(prob, geom, bound, mesh, "cyl2")

    ! Write cylindrial model, cylinder 2
    call Basepair_Chimera_Cylinder(prob, geom, bound, mesh, "cyl2")

    ! Write Chimera file for base pairs
    call Basepair_Chimera_Mesh(prob, geom, mesh)

    ! Write cross-sectional geometry
    call Basepair_Chimera_Cross_Geometry(prob, geom)

    ! Write edge length
    call Basepair_Write_Edge_Length(prob, geom)
!stop
end subroutine Basepair_Discretize

! ---------------------------------------------------------------------------------------

! Count the number of basepairs
! Last updated on Fri 17 Mar 2017 by Hyungmin
subroutine Basepair_Count_Basepair(prob, geom, mesh)
    type(ProbType), intent(in)    :: prob
    type(GeomType), intent(in)    :: geom
    type(MeshType), intent(inout) :: mesh

    double precision :: length, pos_1(3), pos_2(3)
    integer :: i, count

    ! Find total number of elements and conns
    do i = 1, geom.n_croL
        pos_1(1:3) = geom.croP(geom.croL(i).poi(1)).pos(1:3)
        pos_2(1:3) = geom.croP(geom.croL(i).poi(2)).pos(1:3)

        length = Size_Vector(pos_2(1:3) - pos_1(1:3))
        count  = nint(length / para_dist_bp)

        ! Increase the number of nodes and conns
        mesh.n_node = mesh.n_node + count + 1
        mesh.n_ele  = mesh.n_ele  + count

        ! Check minimum edge length
        if( (geom.sec.types == "square"    .and. prob.n_bp_edge - 1 > count ) .or. &
            (geom.sec.types == "honeycomb" .and. prob.n_bp_edge - 2 > count ) ) then
            write(0, "(a)"), "Error - edge length : Basepair_Count_Node"
            stop
        end if
    end do

    ! Print progress
    do i = 0, 11, 11
        call Space(i, 6)
        write(i, "(a)"), "4.1. Pre-calculate the number of basepairs"
        call Space(i, 11)
        write(i, "(a)"), "* The number of multiple points : "//trim(adjustl(Int2Str(geom.n_croP)))
        call Space(i, 11)
        write(i, "(a)"), "* The number of multiple lines  : "//trim(adjustl(Int2Str(geom.n_croL)))
        call Space(i, 11)
        write(i, "(a)"), "* The number of basepairs       : "//trim(adjustl(Int2Str(mesh.n_node)))
        call Space(i, 11)
        write(i, "(a)"), "* The number of basepair conns  : "//trim(adjustl(Int2Str(mesh.n_ele)))
        write(i, "(a)")
    end do
end subroutine Basepair_Count_Basepair

! ---------------------------------------------------------------------------------------

! Generate the basepair model
! Last updated on Fri 17 Mar 2017 by Hyungmin
subroutine Basepair_Generate_Basepair(geom, bound, mesh)
    type(GeomType),  intent(in)    :: geom
    type(BoundType), intent(inout) :: bound
    type(MeshType),  intent(inout) :: mesh

    double precision :: length, pos_1(3), pos_2(3)
    integer :: i, j, k, m, count, n_node, node_start, n_conn
    integer :: poi_1, poi_2, poi_arm

    ! Print progress
    do i = 0, 11, 11
        call Space(i, 6)
        write(i, "(a)"), "4.2. Discretize multiple lines into basepairs"
    end do

    ! Allocate and initialize mesh data
    allocate(mesh.node(mesh.n_node))
    allocate(mesh.ele(mesh.n_ele))
    call Mani_Init_MeshType(mesh)

    ! Initialize the number of nodes and conns
    n_node = 0
    n_conn = 0

    ! Dicretize and set connvectivity
    do i = 1, geom.n_croL

        pos_1(1:3) = geom.croP(geom.croL(i).poi(1)).pos(1:3)
        pos_2(1:3) = geom.croP(geom.croL(i).poi(2)).pos(1:3)
        length     = Size_Vector(pos_2(:) - pos_1(:))
        count      = nint(length / para_dist_bp)

        ! Set the first base pair position
        n_node = n_node + 1

        ! Set nodal position and information at the starting point
        mesh.node(n_node).id       = n_node
        mesh.node(n_node).bp       = 1
        mesh.node(n_node).sec      = geom.croL(i).sec
        mesh.node(n_node).iniL     = geom.croL(i).iniL
        mesh.node(n_node).croL     = i
        mesh.node(n_node).pos(1:3) = pos_1(1:3)

        ! Set connectivity of base pairs
        if(mod(geom.croL(i).sec, 2) == 0) then
            ! Positive z-direction
            mesh.node(n_node).up = n_node + 1
            mesh.node(n_node).dn = -1
        else
            ! Negative z-direction
            mesh.node(n_node).up = -1
            mesh.node(n_node).dn = n_node + 1
        end if

        ! For junction connectivity
        node_start = n_node

        ! Discretize edge from the following node
        do j = 1, count

            ! Connectivity and information for new base pairs
            n_node = n_node + 1

            mesh.node(n_node).id   = n_node
            mesh.node(n_node).bp   = j + 1
            mesh.node(n_node).sec  = geom.croL(i).sec
            mesh.node(n_node).iniL = geom.croL(i).iniL
            mesh.node(n_node).croL = i

            ! Find position vectors -> [ (mx2+nx1)/(m+n) (my2+ny1)/(m+n) (mz2+nz1)/(m+n) ]
            mesh.node(n_node).pos(1:3) = (j*pos_2(1:3) + (count-j)*pos_1(1:3)) / (j+(count-j))

            ! Set base pair connectivity
            if(mod(geom.croL(i).sec, 2) == 0) then

                ! Positive z-direction
                mesh.node(n_node).dn = n_node - 1
                if(j == count) then
                    mesh.node(n_node).up = -1
                else
                    mesh.node(n_node).up = n_node + 1
                end if
            else

                ! Negative z-direction
                mesh.node(n_node).up = n_node - 1
                if(j == count) then
                    mesh.node(n_node).dn = -1
                else
                    mesh.node(n_node).dn = n_node + 1
                end if
            end if

            ! Set finite element connectivity
            n_conn = n_conn + 1
            mesh.ele(n_conn).cn(1) = n_node - 1
            mesh.ele(n_conn).cn(2) = n_node
        end do

        ! ==================================================
        ! Set junction connectivity
        ! ==================================================
        poi_1 = geom.croL(i).poi(1)   ! Start point
        poi_2 = geom.croL(i).poi(2)   ! End point
        do j = 1, bound.n_junc
            do k = 1, bound.junc(j).n_arm
                do m = 1, geom.n_sec

                    ! # of geom.n_modP is equal to geom.n_croP / geom.n_croP
                    !poi_arm = bound.junc(j).modP(k) + (m - 1) * geom.n_croP / geom.n_sec
                    poi_arm = bound.junc(j).croP(k, m)

                    if(poi_1 == poi_arm) bound.junc(j).node(k, m) = node_start
                    if(poi_2 == poi_arm) bound.junc(j).node(k, m) = n_node
                end do
            end do
        end do

        ! Print progress
        write(11, "(i20$  )"), i
        write(11, "(a, i3$)"), " th line (",             n_node-node_start + 1
        write(11, "(a, i6$)"), "-bp) - start node # : ", node_start
        write(11, "(a, i6$)"), ", end node # : ",        n_node
        write(11, "(a, i3$)"), ", sec # : ",             geom.croL(i).sec
        write(11, "(a, i3 )"), ", init edge # : ",       geom.croL(i).iniL
    end do
    write(0, "(a)"); write(11, "(a)")
end subroutine Basepair_Generate_Basepair

! ---------------------------------------------------------------------------------------

! Set sectional connection at the junction
! Last updated on Thu 09 Mar 2017 by Hyungmin
subroutine Basepair_Set_Conn_Junction(geom, bound, mesh)
    type(GeomType),  intent(inout) :: geom
    type(BoundType), intent(inout) :: bound
    type(MeshType),  intent(inout) :: mesh

    integer, allocatable, dimension(:,:) :: connect
    integer, allocatable, dimension(:)   :: node_con
    integer :: node_cur, iniL_cur, croL_cur, node_com, iniL_com, croL_com
    integer :: col_cur, row_cur, sec_cur, col_com, row_com, sec_com
    integer :: i, j, k, m, n, count, n_column, nei_line(2)
    character(10) :: dir_cur, dir_com

    ! Print progress
    do i = 0, 11, 11
        call Space(i, 6)
        write(i, "(a)"), "4.3. Set connection for the junction"
        call Space(i, 11)
        write(i, "(a)"), "* The number of junctions             : "//trim(adjustl(Int2Str(bound.n_junc)))
        call Space(i, 11)
        write(i, "(a)"), "* The number of duplexes on each edge : "//trim(adjustl(Int2Str(geom.n_sec)))
        write(i, "(a)")
    end do

    ! The number of junction
    do i = 1, bound.n_junc

        ! Allocate arrary to store the nodes to be joined each other
        allocate(connect(bound.junc(i).n_arm*geom.n_sec, 2))

        ! all nodes in the junction
        do j = 1, geom.n_sec
            do k = 1, bound.junc(i).n_arm

                ! Find the current node and its initial edge
                node_cur = bound.junc(i).node(k, j)
                iniL_cur = mesh.node(node_cur).iniL

                croL_cur = mesh.node(node_cur).croL
                sec_cur  = Geom.croL(croL_cur).sec
                col_cur  = Geom.sec.posC(sec_cur + 1)
                row_cur  = Geom.sec.posR(sec_cur + 1)
                n_column = geom.sec.maxC-geom.sec.minC + 1

                if(geom.sec.posC(mesh.node(node_cur).sec + 1) < n_column / 2 + 1) then
                    ! Left and positivie sign
                    nei_line(1:2) = geom.iniL(iniL_cur).neiL(1:2, 1)
                else
                    ! Right and negative sign
                    nei_line(1:2) = geom.iniL(iniL_cur).neiL(1:2, 2)
                end if

                ! Exception for the open boundary
                if(nei_line(1) == -1 .and. nei_line(2) == -1) then
                    bound.junc(i).type_conn(j) = 1
                    connect((j-1)*bound.junc(i).n_arm+k, 1) = node_cur
                    connect((j-1)*bound.junc(i).n_arm+k, 2) = -1
                    cycle
                end if

                ! Allocate array to save candinate neighbor nodes
                allocate(node_con(geom.n_sec))

                ! Find the comparing node and its initial edge
                do m = 1, geom.n_sec
                    do n = 1, bound.junc(i).n_arm
                        node_com = bound.junc(i).node(n, m)
                        iniL_com = mesh.node(node_com).iniL

                        if(nei_line(1) == iniL_com .or. nei_line(2) == iniL_com) then
                            node_con(m) = node_com
                        end if
                    end do
                end do

                ! Find proper node among node_con, in which node_cur and node_con(1:geom.n_sec) are known
                ! Check the initial line whether inword or outward vector to junction
                dir_cur = Basepair_Get_Direction_IniL(geom, mesh, node_cur)

                ! Loop for every comparing node
                do m = 1, geom.n_sec

                    croL_com = mesh.node(node_con(m)).croL
                    sec_com  = Geom.croL(croL_com).sec
                    col_com  = Geom.sec.posC(sec_com + 1)
                    row_com  = Geom.sec.posR(sec_com + 1)

                    ! Get the edge direction of comparing nodes, inward or outward to the junction
                    dir_com = Basepair_Get_Direction_IniL(geom, mesh, node_con(m))

                    ! The connection will happen at the node with the same row
                    if(row_cur == row_com) then

                        ! If direction is the same and column index is reverse to original one
                        if(dir_cur == dir_com .and. col_cur == Geom.sec.maxC - col_com + 1) then
                            connect((j-1)*bound.junc(i).n_arm+k, 1) = node_cur
                            connect((j-1)*bound.junc(i).n_arm+k, 2) = node_con(m)
                        else if(dir_cur /= dir_com .and. col_cur == col_com) then
                            connect((j-1)*bound.junc(i).n_arm+k, 1) = node_cur
                            connect((j-1)*bound.junc(i).n_arm+k, 2) = node_con(m)
                        end if
                    end if
                end do

                ! Deallocate memory
                deallocate(node_con)
            end do
        end do

        ! Set neighbor connection at junction
        ! connect(j, 1) : current node -> connect(j, 2) : node to be connected with connect(j, 1)
        do j = 1, geom.n_sec*bound.junc(i).n_arm
            bound.junc(i).conn(j, 1) = connect(j, 1)
            bound.junc(i).conn(j, 2) = connect(j, 2)

            bound.junc(i).type_conn(j) = 1
        end do

        ! Deallocate memory
        deallocate(connect)
    end do

    ! Exception for the open geometry with conn == -1
    do i = 1, bound.n_junc
        do j = 1, geom.n_sec*bound.junc(i).n_arm
            if(bound.junc(i).conn(j, 2) == -1) then
                do k = j + 1, geom.n_sec*bound.junc(i).n_arm
                    if(bound.junc(i).conn(k, 2) == -1) then
                        bound.junc(i).conn(j, 2) = bound.junc(i).conn(k, 1)
                        bound.junc(i).conn(k, 2) = bound.junc(i).conn(j, 1)
                    end if
                end do
            end if
        end do
    end do

    ! ==================================================
    !
    ! Internal node connection for self connection route
    !
    ! ==================================================
    ! Loop for junction
    do i = 1, bound.n_junc
        do j = 1, bound.junc(i).n_arm

            do m = 1, geom.n_sec
                node_cur = bound.junc(i).node(j, m)
                sec_cur  = mesh.node(node_cur).sec

                do n = 1, geom.n_sec
                    node_com = bound.junc(i).node(j, n)
                    sec_com  = mesh.node(node_com).sec

                    ! The section number should be different
                    if(sec_cur == sec_com) cycle

                    ! Check whether self or neighbor connection
                    if(geom.sec.conn(sec_cur + 1) /= sec_com) cycle

                    ! Set self connection at junction
                    bound.junc(i).conn((m-1)*bound.junc(i).n_arm+j, 1) = node_cur
                    bound.junc(i).conn((m-1)*bound.junc(i).n_arm+j, 2) = node_com

                    bound.junc(i).type_conn((m-1)*bound.junc(i).n_arm+j) = 2
                end do
            end do
        end do
    end do

    ! Print bound data
    !call Basepair_Print_Bound_Data(geom, bound)
end subroutine Basepair_Set_Conn_Junction

! ---------------------------------------------------------------------------------------

! Print bound data
! Last updated on Thu 09 Mar 2017 by Hyungmin
subroutine Basepair_Print_Bound_Data(geom, bound)
    type(GeomType),  intent(in) :: geom
    type(BoundType), intent(in) :: bound

    integer :: i, j, k

    ! Check boundary data
    do i = 1, bound.n_junc
        write(0, "(3i)"), i, bound.junc(i).n_arm, bound.junc(i).poi_c
        call Space(0, 20)
        write(0, "(3f8.3)"), Rad2Deg(bound.junc(i).ref_ang), Rad2Deg(bound.junc(i).tot_ang), bound.junc(i).gap

        ! Initial lines
        call Space(0, 20)
        do j = 1, bound.junc(i).n_arm
            write(0, "(i4$)"), bound.junc(i).iniL(j)
        end do
        write(0, "(a)")

        ! Seperated points
        call Space(0, 20)
        do j = 1, bound.junc(i).n_arm
            write(0, "(i4$)"), bound.junc(i).modP(j)
        end do
        write(0, "(a)")

        ! Multiple points
        call Space(0, 20)
        do j = 1, bound.junc(i).n_arm
            do k = 1, geom.n_sec
                write(0, "(i4$)"), bound.junc(i).croP(j, k)
            end do
            write(0, "(a$)"), ","
        end do
        write(0, "(a)")

        ! Nodes
        call Space(0, 20)
        do j = 1, bound.junc(i).n_arm
            do k = 1, geom.n_sec
                write(0, "(i4$)"), bound.junc(i).node(j, k)
            end do
            write(0, "(a$)"), ","
        end do
        write(0, "(a)"); write(0, "(a)")

        ! Node connectivity
        call Space(0, 20)
        do j = 1, geom.n_sec*bound.junc(i).n_arm
            write(0, "(i8$)"), bound.junc(i).conn(j, 1)
        end do
        write(0, "(a)")
        call Space(0, 20)
        do j = 1, geom.n_sec*bound.junc(i).n_arm
            write(0, "(i8$)"), bound.junc(i).conn(j, 2)
        end do
        write(0, "(a)")

        ! Junction connection type
        call Space(0, 20)
        do j = 1, geom.n_sec*bound.junc(i).n_arm
            write(0, "(i8$)"), bound.junc(i).type_conn(j)
        end do
        write(0, "(a)")
        write(0, "(a)"); write(0, "(a)")
    end do
end subroutine Basepair_Print_Bound_Data

! ---------------------------------------------------------------------------------------

! Get direction, inward or outward to the junction
! Last updated on Sunday 20 Mar 2016 by Hyungmin
function Basepair_Get_Direction_IniL(geom, mesh, node) result (direction)
    Type(GeomType), intent(in) :: geom
    type(MeshType), intent(in) :: mesh
    integer,        intent(in) :: node

    integer :: croL, sec
    character(10) :: direction

    ! Find cross-sectional edge and section ID
    croL = mesh.node(node).croL
    sec  = geom.croL(croL).sec

    ! Check the line whether inword or outward vector to junction
    if(mesh.node(node).dn      == -1 .and. mod(sec, 2) == 0) then
        direction = "outward"
    else if(mesh.node(node).dn == -1 .and. mod(sec, 2) /= 0) then
        direction = "inward"
    else if(mesh.node(node).up == -1 .and. mod(sec, 2) == 0) then
        direction = "inward"
    else if(mesh.node(node).up == -1 .and. mod(sec, 2) /= 0) then
        direction = "outward"
    else
        write(0, "(a$)"), "Error - The node_com does not lay on the junction : "
        write(0, "(a )"), "Basepair_Get_Direction_IniL"
        stop
    end if
end function Basepair_Get_Direction_IniL

! ---------------------------------------------------------------------------------------

! Write cylindrial model with orientation
! Last updated on Fri 17 Mar 2017 by Hyungmin
subroutine Basepair_Chimera_Cylinder_Ori(prob, geom, bound, mesh, mode)
    type(ProbType),  intent(in) :: prob
    type(GeomType),  intent(in) :: geom
    type(BoundType), intent(in) :: bound
    type(MeshType),  intent(in) :: mesh
    character(*),    intent(in) :: mode

    double precision :: pos_1(3), pos_2(3)
    double precision :: ang_BP, ang_init, ang_start, ang_scaf
    double precision :: pos_scaf(3), t(3,3), e(3,3), rot(3,3)
    integer :: i, j, k, node
    logical :: f_axis
    character(200) :: path

    if(para_write_501 == .false.) return 

    ! Set option
    f_axis = para_chimera_axis

    path = trim(prob.path_work1)//trim(prob.name_file)//"_"
    open(unit=501, file=trim(path)//trim(mode)//"_ori.bild", form="formatted")

    ! Write cylinder model base on cross-sectional edges
    write(501, "(a, 3f9.4)"), ".color ", dble(prob.color(1:3))/255.0d0
    do i = 1, geom.n_croL

        pos_1(1:3) = geom.croP(geom.croL(i).poi(1)).pos(1:3)
        pos_2(1:3) = geom.croP(geom.croL(i).poi(2)).pos(1:3)

        write(501, "(a$    )"), ".cylinder "
        write(501, "(3f9.3$)"), pos_1(1:3)
        write(501, "(3f9.3$)"), pos_2(1:3)
        write(501, "(1f9.3 )"), para_rad_helix + para_gap_helix/2.0d0
    end do

    ! Angle rotated between neighboring base-pairs
    if(geom.sec.types == "square") then
        ang_BP = 360.0d0*3.0d0/32.0d0     ! 360/10.67 = 33.75
    else if(geom.sec.types == "honeycomb") then
        ang_BP = 360.0d0*2.0d0/21.0d0     ! 360/10.5  = 34.28
    end if

    ! Loop for junction
    do i = 1, bound.n_junc

        ! Loop for every node at each junction
        do j = 1, geom.n_sec
            do k = 1, bound.junc(i).n_arm

                node = bound.junc(i).node(k, j)

                ! Find angle of bases corresponding to basepair id
                if(mod(mesh.node(node).sec, 2) == 0) then

                    ! Positive z-direction
                    if(geom.sec.types == "square") then
                        ang_init = 180.0d0 - ang_BP / 2.0d0 + ang_BP
                    else if(geom.sec.types == "honeycomb") then
                        if(geom.sec.dir ==  90) ang_init = 90.0d0
                        if(geom.sec.dir == 150) ang_init = 90.0d0+60.0d0
                        if(geom.sec.dir == -90) ang_init = 270.0d0
                    end if

                    ang_start = dmod(ang_init  + ang_BP*dble(para_start_bp_ID),     360.0d0)
                    ang_start = dmod(ang_start + ang_BP*dble(mesh.node(node).bp-1), 360.0d0)
                    ang_scaf  = dmod(ang_start + para_ang_correct,                  360.0d0)
                else if(mod(mesh.node(node).sec, 2) == 1) then

                    ! Negative z-direction
                    if(geom.sec.types == "square") then
                        ang_init = 0.0d0 - ang_BP / 2.0d0 + ang_BP
                    else if(geom.sec.types == "honeycomb") then
                        if(geom.sec.dir ==  90) ang_init = 270.0d0
                        if(geom.sec.dir == 150) ang_init = 270.0d0+60.0d0
                        if(geom.sec.dir == -90) ang_init = 90.0d0
                    end if

                    ang_start = dmod(ang_init  + ang_BP*dble(para_start_bp_ID),     360.0d0)
                    ang_start = dmod(ang_start + ang_BP*dble(mesh.node(node).bp-1), 360.0d0)
                    ang_scaf  = dmod(ang_start - para_ang_correct,                  360.0d0)
                end if

                ! Make negative angles to positive angles
                if(ang_scaf < 0.0d0) then
                    ang_scaf = dmod(360.0d0 + ang_scaf, 360.0d0)
                end if

                ! Global Cartesian coordinate
                e(1,:) = 0.0d0; e(2,:) = 0.0d0; e(3,:) = 0.0d0
                e(1,1) = 1.0d0; e(2,2) = 1.0d0; e(3,3) = 1.0d0

                ! Local coordinate system
                t(1, 1:3) = geom.iniL(mesh.node(node).iniL).t(1, 1:3)
                t(2, 1:3) = geom.iniL(mesh.node(node).iniL).t(2, 1:3)
                t(3, 1:3) = geom.iniL(mesh.node(node).iniL).t(3, 1:3)

                ! The direction cosines of the coordinate transformation
                rot(1,1) = dot_product(e(1,:), t(1,:))
                rot(1,2) = dot_product(e(1,:), t(2,:))
                rot(1,3) = dot_product(e(1,:), t(3,:))

                rot(2,1) = dot_product(e(2,:), t(1,:))
                rot(2,2) = dot_product(e(2,:), t(2,:))
                rot(2,3) = dot_product(e(2,:), t(3,:))

                rot(3,1) = dot_product(e(3,:), t(1,:))
                rot(3,2) = dot_product(e(3,:), t(2,:))
                rot(3,3) = dot_product(e(3,:), t(3,:))

                ! Set base position vector for the scaffold strand
                pos_scaf(1) = para_rad_helix * 0.0d0
                pos_scaf(2) = para_rad_helix * dsin(-ang_scaf * pi/180.0d0)
                pos_scaf(3) = para_rad_helix * dcos(-ang_scaf * pi/180.0d0)
                pos_scaf(:) = mesh.node(node).pos(:) + matmul(rot(:, :), pos_scaf(:))

                ! Write sphere to represent start and end edge
                write(501, "(a     )"), ".color steel blue"
                write(501, "(a$    )"), ".sphere "
                write(501, "(3f9.3$)"), mesh.node(node).pos(1:3)
                write(501, "(1f9.3 )"), 0.2d0

                write(501, "(a     )"), ".color yellow"
                write(501, "(a$    )"), ".arrow "
                write(501, "(3f8.2$)"), mesh.node(node).pos(1:3)
                write(501, "(3f8.2$)"), pos_scaf(1:3)
                write(501, "(2f8.2 )"), 0.09d0, 0.18d0
            end do
        end do
    end do

    ! Write global axis
    if(f_axis == .true.) then
        write(501, "(a)"), ".translate 0.0 0.0 0.0"
        write(501, "(a)"), ".scale 0.5"
        write(501, "(a)"), ".color grey"
        write(501, "(a)"), ".sphere 0 0 0 0.5"      ! Center
        write(501, "(a)"), ".color red"             ! x-axis
        write(501, "(a)"), ".arrow 0 0 0 4 0 0 "
        write(501, "(a)"), ".color blue"            ! y-axis
        write(501, "(a)"), ".arrow 0 0 0 0 4 0 "
        write(501, "(a)"), ".color yellow"          ! z-axis
        write(501, "(a)"), ".arrow 0 0 0 0 0 4 "
    end if

    close(unit=501)
end subroutine Basepair_Chimera_Cylinder_Ori

! ---------------------------------------------------------------------------------------

! Write cylindrial model
! Last updated on Fri 17 Mar 2017 by Hyungmin
subroutine Basepair_Chimera_Cylinder(prob, geom, bound, mesh, mode)
    type(ProbType),  intent(in) :: prob
    type(GeomType),  intent(in) :: geom
    type(BoundType), intent(in) :: bound
    type(MeshType),  intent(in) :: mesh
    character(*),    intent(in) :: mode

    double precision :: pos_1(3), pos_2(3), radius
    integer :: i, j, node, node_1, node_2
    logical :: f_axis, f_ori
    character(200) :: path

    if(para_write_502 == .false.) return

    ! Set flag for drawing option
    f_axis = para_chimera_axis
    f_ori  = para_chimera_502_ori

    path = trim(prob.path_work1)//trim(prob.name_file)//"_"
    open(unit=502, file=trim(path)//trim(mode)//".bild", form="formatted")

    ! Cylinder radius
    radius = para_rad_helix + para_gap_helix / 2.0d0

    ! Write cylinder model base on edges
    write(502, "(a, 3f9.4)"), ".color ", dble(prob.color(1:3))/255.0d0
    do i = 1, geom.n_croL
        pos_1(1:3) = geom.croP(geom.croL(i).poi(1)).pos(1:3)
        pos_2(1:3) = geom.croP(geom.croL(i).poi(2)).pos(1:3)

        write(502, "(a$    )"), ".cylinder "
        write(502, "(3f9.3$)"), pos_1(1:3)
        write(502, "(3f9.3$)"), pos_2(1:3)
        write(502, "(1f9.3 )"), radius
    end do

    ! Write connection on the section
    do i = 1, bound.n_junc
        do j = 1, geom.n_sec * bound.junc(i).n_arm

            node_1   = bound.junc(i).conn(j, 1)
            node_2   = bound.junc(i).conn(j, 2)
            pos_1(:) = mesh.node(node_1).pos(:)
            pos_2(:) = mesh.node(node_2).pos(:)

            if(bound.junc(i).type_conn(j) == 1) then
                ! For neighbor connection
                write(502, "(a)"), ".color red"
            else if(bound.junc(i).type_conn(j) == 2) then
                ! For self connection
                write(502, "(a)"), ".color steel blue"
            end if

            ! Exception module for two closed positions
            if( (dabs(pos_1(1) - pos_2(1)) < 0.001d0) .and. &
                (dabs(pos_1(2) - pos_2(2)) < 0.001d0) .and. &
                (dabs(pos_1(3) - pos_2(3)) < 0.001d0) ) then
                cycle
            end if

            write(502, "(a$    )"), ".cylinder "
            write(502, "(3f9.3$)"), pos_1(1:3)
            write(502, "(3f9.3$)"), pos_2(1:3)
            write(502, "(1f9.3 )"), radius*0.1d0

            ! Write sphere to represent start and end edge
            write(502, "(a     )"), ".color steel blue"
            write(502, "(a$    )"), ".sphere "
            write(502, "(3f9.3$)"), pos_1(1:3)
            write(502, "(1f9.3 )"), 0.2d0
            write(502, "(a$    )"), ".sphere "
            write(502, "(3f9.3$)"), pos_2(1:3)
            write(502, "(1f9.3 )"), 0.2d0
        end do
    end do

    ! Print initial geometry with cylindrical model 1
    if(mode == "cyl1") then

        ! Write initial points
        write(502, "(a)"), ".color red"

        do i = 1, geom.n_iniP
            write(502, "(a$    )"), ".sphere "
            write(502, "(3f9.2$)"), geom.iniP(i).pos(1:3)
            write(502, "(1f9.2 )"), 0.5d0 * 0.6d0
        end do

        ! Write initial edges
        write(502, "(a)"), ".color dark green"
        do i = 1, bound.n_junc
            do j = 1, bound.junc(i).n_arm
                pos_1(1:3) = geom.iniP(geom.iniL(bound.junc(i).iniL(j)).iniP(1)).pos(1:3)
                pos_2(1:3) = geom.iniP(geom.iniL(bound.junc(i).iniL(j)).iniP(2)).pos(1:3)

                write(502,"(a$    )"), ".cylinder "
                write(502,"(3f9.2$)"), pos_1(1:3)
                write(502,"(3f9.2$)"), pos_2(1:3)
                write(502,"(1f9.2 )"), 0.2d0 * 0.6d0
            end do
        end do
    end if

    ! Write option corresponding to flag
    if(f_ori == .true.) then
        do i = 1, mesh.n_node
            if(mesh.node(i).up == -1) then

                ! Inward direction with red dot
                write(502, "(a)"), ".color red"
                pos_1(1:3) = mesh.node(i).pos(1:3)
            else if(mesh.node(i).dn == -1) then

                ! Outward direction with yellow dot
                write(502, "(a)"), ".color yellow"
                pos_1(1:3) = mesh.node(i).pos(1:3)
            end if

            write(502, "(a$    )"), ".sphere "
            write(502, "(3f9.3$)"), pos_1(1:3)
            write(502, "(1f9.3 )"), 0.25d0
        end do
    end if

    ! Write global axis
    if(f_axis == .true.) then
        write(502, "(a)"), ".translate 0.0 0.0 0.0"
        write(502, "(a)"), ".scale 0.5"
        write(502, "(a)"), ".color grey"
        write(502, "(a)"), ".sphere 0 0 0 0.5"      ! Center
        write(502, "(a)"), ".color red"             ! x-axis
        write(502, "(a)"), ".arrow 0 0 0 4 0 0 "
        write(502, "(a)"), ".color blue"            ! y-axis
        write(502, "(a)"), ".arrow 0 0 0 0 4 0 "
        write(502, "(a)"), ".color yellow"          ! z-axis
        write(502, "(a)"), ".arrow 0 0 0 0 0 4 "
    end if

    close(unit=502)
end subroutine Basepair_Chimera_Cylinder

! ---------------------------------------------------------------------------------------

! Modify the length of the duplex at the junction
! Last updated on Fri 17 Mar 2017 by Hyungmin
subroutine Basepair_Modify_Junction(geom, bound, mesh)
    type(GeomType),  intent(inout) :: geom
    type(BoundType), intent(inout) :: bound
    type(MeshType),  intent(inout) :: mesh

    integer, allocatable, dimension(:,:) :: conn
    integer, allocatable, dimension(:)   :: t_conn

    integer :: node_cur, node_com, sec, col, row
    integer :: i, j, k, cn, n_conn, n_move
    logical :: b_con

    ! Print progress
    do i = 0, 11, 11
        call Space(i, 6)
        write(i, "(a)"), "4.4. Modify the length of duplex at the junction"
        call Space(i, 11)
        write(i, "(a)"), "* Find the proper length of duplex at the junction"
        call Space(i, 11)
        write(i, "(a)"), "* Update junction data with updated nodes"
        call Space(i, 11)
        write(i, "(a)"), "* Detailed information on junction connectivity"
    end do

    ! Loop for junction
    do i = 1, bound.n_junc

        ! Print progress bar
        call Mani_Progress_Bar(i, bound.n_junc)

        ! Allocate conn wihout duplicated data, which is the half of connection data
        n_conn = geom.n_sec * bound.junc(i).n_arm / 2
        allocate(conn(n_conn, 2))
        allocate(t_conn(n_conn))

        ! Loop for junction nodes
        cn = 0
        do j = 1, n_conn * 2

            ! Compare with previous storaged data
            b_con = .false.
            do k = 1, cn
                if(conn(k, 1) == bound.junc(i).conn(j, 1)) then
                    if(conn(k, 2) == bound.junc(i).conn(j, 2)) then
                        b_con = .true.
                    end if
                else if(conn(k, 1) == bound.junc(i).conn(j, 2)) then
                    if(conn(k, 2) == bound.junc(i).conn(j, 1)) then
                        b_con = .true.
                    end if
                end if
            end do

            ! If there is no entity in existing array
            if(b_con == .false.) then
                cn            = cn + 1
                conn(cn, 1:2) = bound.junc(i).conn(j, 1:2)
                t_conn(cn)    = bound.junc(i).type_conn(j)
            end if
        end do

        ! Print progress
        ! The data conn contains information on which node is connected to the current node
        ! The data t_conn contains connection type, 1 - neighboring 2 - self connection
        write(11, "(i20$)"), i
        write(11, "(a$  )"), " th junc -> # of arms : "
        write(11, "(i7  )"), n_conn
        do j = 1, n_conn
            write(11, "(i30, a$)"), conn(j, 1), " th node --> "
            write(11, "(i7,  a$)"), conn(j, 2), " th node,"
            write(11, "(a12, i5)"), "type :", t_conn(j)
        end do

        ! Modify the edge length
        do j = 1, n_conn

            ! Modify junction depending on connection type
            if(t_conn(j) == 2) then

                ! ============================================================
                !
                ! Self-connection modification
                !
                ! ============================================================

                ! Assign node from node connection data
                node_cur = conn(j, 1)
                node_com = conn(j, 2)

                ! Vertex modification - 1: constant length, 2: decreased length, 3: closet crossover
                if(para_vertex_modify == "const") then

                    ! ------------------------------------------------------------
                    ! Self-connectin #1 - constant edge length
                    ! ------------------------------------------------------------
                    ! Set node connection as self-connection
                    mesh.node(node_cur).conn = 2
                    mesh.node(node_com).conn = 2
                    !cycle

                    ! ************************************************************
                    ! Find closet crossovers nearby
                    n_move = Basepair_Find_Xover_Nearby(geom, bound, mesh, node_cur, node_com)

                    if(n_move > 0) then
                        ! Increase basepair with certain size, n_move
                        call Basepair_Increase_Basepair(geom, bound, mesh, node_cur, node_com, n_move)
                    else if(n_move < 0) then
                        ! Decrease basepair with certain size making ghost nodes
                        call Basepair_Decrease_Basepair(geom, bound, mesh, node_cur, node_com, abs(n_move))
                    end if
                    ! ************************************************************
                    cycle

                else if(para_vertex_modify == "mod1") then

                    ! ------------------------------------------------------------
                    ! Self-connectin #2 - Decrease edge length to avoid crash
                    ! ------------------------------------------------------------
                    sec = mesh.node(node_cur).sec
                    row = geom.sec.posR(sec + 1)
                    col = geom.sec.posC(sec + 1)

                    ! Check the section below the reference row
                    !if( (row > geom.sec.ref_row) .or. &
                    !    (row == geom.sec.ref_row .and. col /= geom.sec.ref_maxC .and. col /= geom.sec.ref_minC) ) then
                    if(row >= geom.sec.ref_row) then
                        mesh.node(node_cur).conn = 2
                        mesh.node(node_com).conn = 2
                        cycle
                    end if

                    ! Check ghost node to be deleted
                    call Basepair_Make_Ghost_Node(geom, bound, mesh, node_cur, node_com)

                else if(para_vertex_modify == "mod2") then

                    ! ------------------------------------------------------------
                    ! Self-connectin #3 - modification using closet crossover
                    ! ------------------------------------------------------------
                    ! Find closet crossovers nearby
                    n_move = Basepair_Find_Xover_Nearby(geom, bound, mesh, node_cur, node_com)

                    if(n_move == 0) then

                        ! No modifiction, set modified self connection to skip sticky end
                        mesh.node(node_cur).conn = 4
                        mesh.node(node_com).conn = 4
                        cycle
                    else if(n_move > 0) then

                        ! Increase basepair with certain size, n_move
                        call Basepair_Increase_Basepair(geom, bound, mesh, node_cur, node_com, n_move)
                    else if(n_move < 0) then

                        ! Decrease basepair with certain size making ghost nodes
                        call Basepair_Decrease_Basepair(geom, bound, mesh, node_cur, node_com, abs(n_move))
                    end if

                end if
            else

                ! ============================================================
                !
                ! Self-connection modification, increase edge legnth to fill hole
                !
                ! ============================================================
                ! Node and sectional information
                node_cur = conn(j, 1)
                node_com = conn(j, 2)
                sec      = mesh.node(node_cur).sec
                col      = Geom.sec.posC(sec + 1)
                row      = Geom.sec.posR(sec + 1)

                ! Set nodes as modified neighbor connection
                mesh.node(node_cur).conn = 3
                mesh.node(node_com).conn = 3

                ! If the node is reference, set 1 as node connectivity
                ! -1 - no-connection, 1 - reference, 2 - self, 3 - modified neighbor, 4 - modified self
                if(row == geom.sec.ref_row) then
                    if(col == geom.sec.ref_maxC .or. col == geom.sec.ref_minC) then
                        mesh.node(node_cur).conn = 1
                        mesh.node(node_com).conn = 1
                    end if
                end if

                ! Increase edge length of the duplex to fill junctional gap
                call Basepair_Increase_Edge(geom, bound, mesh, node_cur, node_com)
            end if
        end do

        ! Deallocate memory
        deallocate(conn)
        deallocate(t_conn)
    end do
    write(0, "(a)"); write(11, "(a)")
end subroutine Basepair_Modify_Junction

! ---------------------------------------------------------------------------------------

! Find crossovers nearby from current and comparing nodes
! Last updated on Friday 05 August 2016 by Hyungmin
function Basepair_Find_Xover_Nearby(geom, bound, mesh, node_cur, node_com) result(n_move)
    type(geomType),  intent(in) :: geom
    type(BoundType), intent(in) :: bound
    type(MeshType),  intent(in) :: mesh
    integer,         intent(in) :: node_cur
    integer,         intent(in) :: node_com

    integer :: n_inside, n_outside, bp_inside, bp_outside, n_move
    integer :: count, sec_cur, sec_com, bp_cur
    logical :: b_inside, b_outside

    sec_cur = mesh.node(node_cur).sec
    sec_com = mesh.node(node_com).sec
    bp_cur  = mesh.node(node_cur).bp

    ! Find crossover nearby manually
    !if(mesh.node(node_cur).dn == -1 .and. sec_cur == 2 .and. sec_com == 3) n_move = -2
    !if(mesh.node(node_cur).dn == -1 .and. sec_cur == 3 .and. sec_com == 2) n_move = -2
    !if(mesh.node(node_cur).up == -1 .and. sec_cur == 2 .and. sec_com == 3) n_move =  3
    !if(mesh.node(node_cur).up == -1 .and. sec_cur == 3 .and. sec_com == 2) n_move =  3
    !if(mesh.node(node_cur).dn == -1 .and. sec_cur == 4 .and. sec_com == 5) n_move =  2
    !if(mesh.node(node_cur).dn == -1 .and. sec_cur == 5 .and. sec_com == 4) n_move =  2
    !if(mesh.node(node_cur).up == -1 .and. sec_cur == 4 .and. sec_com == 5) n_move = -1
    !if(mesh.node(node_cur).up == -1 .and. sec_cur == 5 .and. sec_com == 4) n_move = -1

    bp_inside  = 0
    bp_outside = 0
    n_inside   = 0
    n_outside  = 0

    do
        ! Check crossovers
        b_inside  = Section_Connection_Scaf(geom, sec_cur, sec_com, bp_cur + bp_inside)
        b_outside = Section_Connection_Scaf(geom, sec_cur, sec_com, bp_cur + bp_outside)

        ! Exception when crossover at the first bp exists
        if(n_inside == 0 .and. n_outside == 0 .and. b_inside == .true. .and. b_outside == .true.) then

            if( (mesh.node(node_cur).up == -1 .and. mod(mesh.node(node_cur).sec, 2) == 0) .or. &
                (mesh.node(node_cur).dn == -1 .and. mod(mesh.node(node_cur).sec, 2) == 1) ) then

                if(Section_Connection_Scaf(geom, sec_cur, sec_com, bp_cur - 1) == .true.) then
                    n_move = -1
                else
                    n_move = 0
                end if
            else if( (mesh.node(node_cur).dn == -1 .and. mod(mesh.node(node_cur).sec, 2) == 0) .or. &
                     (mesh.node(node_cur).up == -1 .and. mod(mesh.node(node_cur).sec, 2) == 1) ) then

                if(Section_Connection_Scaf(geom, sec_cur, sec_com, bp_cur - 1) == .true.) then
                    n_move = 0
                else
                    n_move = -1
                end if
            end if

            return
        end if

        ! Check single or double scaffold crossovers
        if(b_inside == .true.) then
            n_inside = n_inside + 1
            if(n_inside == 2) exit
        else if(b_outside == .true.) then
            n_outside = n_outside + 1
            if(n_outside == 1) exit
        end if

        ! Update bp ID
        if(mesh.node(node_cur).dn == -1) then
            if(mod(mesh.node(node_cur).sec, 2) == 0) then
                ! + -> inside, - -> outside
                bp_inside  = bp_inside  + 1
                bp_outside = bp_outside - 1
            else if(mod(mesh.node(node_cur).sec, 2) == 1) then
                ! - -> inside, + -> outside
                bp_inside  = bp_inside  - 1
                bp_outside = bp_outside + 1
            end if
        else if(mesh.node(node_cur).up == -1) then
            if(mod(mesh.node(node_cur).sec, 2) == 0) then
                ! - -> inside, + -> outside
                bp_inside  = bp_inside  - 1
                bp_outside = bp_outside + 1
            else if(mod(mesh.node(node_cur).sec, 2) == 1) then
                ! + -> inside, - ->outside
                bp_inside  = bp_inside  + 1
                bp_outside = bp_outside - 1
            end if
        end if
    end do

    ! Set return values
    if(b_inside == .true.) then
        n_move = -abs(bp_inside)
    else if(b_outside == .true.) then
        n_move = abs(bp_outside)
    else
        n_move = 0
    end if
end function Basepair_Find_Xover_Nearby

! ---------------------------------------------------------------------------------------

! Increase basepair with certain size, n_move
! Last updated on Thursday 04 August 2016 by Hyungmin
subroutine Basepair_Increase_Basepair(geom, bound, mesh, node_cur, node_com, n_move)
    type(geomType),  intent(inout) :: geom
    type(BoundType), intent(inout) :: bound
    type(MeshType),  intent(inout) :: mesh
    integer,         intent(in)    :: node_cur
    integer,         intent(in)    :: node_com
    integer,         intent(in)    :: n_move

    double precision :: vec_dn(3), vec_up(3)
    integer :: i, node_dn, node_up

    ! Set direction, node_dn and node_up
    if(mesh.node(node_cur).up == -1) then

        ! If the direction of current node is downward
        node_dn = node_cur
        node_up = node_com
    else if(mesh.node(node_cur).dn == -1) then

        ! If the direction of current node is upward
        node_dn = node_com
        node_up = node_cur
    end if

    ! Set downward and upward vector
    vec_dn(1:3) = mesh.node(node_dn).pos(:) - mesh.node(mesh.node(node_dn).dn).pos(:)
    vec_up(1:3) = mesh.node(node_up).pos(:) - mesh.node(mesh.node(node_up).up).pos(:)

    ! Add new nodes
    do i = 1, n_move

        ! Add one basepair at the position indicating vector, return updated newly node ID
        call Basepair_Add_Basepair(geom, bound, mesh, node_dn, vec_dn)
        call Basepair_Add_Basepair(geom, bound, mesh, node_up, vec_up)
    end do

    ! Update node connectivity as modified self connection for last nodes
    mesh.node(node_dn).conn = 4
    mesh.node(node_up).conn = 4
end subroutine Basepair_Increase_Basepair

! ---------------------------------------------------------------------------------------

! Decrease basepair with certain size making ghost nodes
! Last updated on Thursday 04 August 2016 by Hyungmin
subroutine Basepair_Decrease_Basepair(geom, bound, mesh, node_cur, node_com, n_move)
    type(geomType),  intent(inout) :: geom
    type(BoundType), intent(inout) :: bound
    type(MeshType),  intent(inout) :: mesh
    integer,         intent(in)    :: node_cur
    integer,         intent(in)    :: node_com
    integer,         intent(in)    :: n_move

    integer :: i, node_dn, node_up

    ! Set direction, node_dn and node_up
    if(mesh.node(node_cur).up == -1) then

        ! If the direction of current node is downward
        node_dn = node_cur
        node_up = node_com
    else if(mesh.node(node_cur).dn == -1) then

        ! If the direction of current node is upward
        node_dn = node_com
        node_up = node_cur
    end if

    ! Make ghost nodes with size, n_move
    do i = 1, n_move
        mesh.node(node_dn).ghost = 1
        mesh.node(node_up).ghost = 1

        node_dn = mesh.node(node_dn).dn
        node_up = mesh.node(node_up).up
    end do

    ! Update node connectivity as modified self connection for last nodes
    mesh.node(node_dn).conn = 4
    mesh.node(node_up).conn = 4
end subroutine Basepair_Decrease_Basepair

! ---------------------------------------------------------------------------------------

! Check ghost node to be deleted
! Last updated on Thursday 28 July 2016 by Hyungmin
subroutine Basepair_Make_Ghost_Node(geom, bound, mesh, node_cur, node_com)
    type(geomType),  intent(inout) :: geom
    type(BoundType), intent(inout) :: bound
    type(MeshType),  intent(inout) :: mesh
    integer,         intent(in)    :: node_cur
    integer,         intent(in)    :: node_com

    integer :: i, n_xover, sec_up, sec_dn
    integer :: id_bp, node_up, node_dn
    logical :: b_nei

    if(mesh.node(node_cur).up == -1) then
        node_dn = mesh.node(node_cur).dn
        node_up = mesh.node(node_com).up
    else
        node_up = mesh.node(node_cur).up
        node_dn = mesh.node(node_com).dn
    end if

    ! Make ghost node
    mesh.node(node_cur).ghost = 1
    mesh.node(node_com).ghost = 1

    ! Count crossovers
    n_xover = 0
    do
        sec_up = mesh.node(node_up).sec
        sec_dn = mesh.node(node_dn).sec
        id_bp  = mesh.node(node_up).bp

        ! Check crossovers
        b_nei = Section_Connection_Scaf(geom, sec_up, sec_dn, id_bp)

        if(b_nei == .true.) then
            n_xover = n_xover + 1
            if(n_xover == 2) exit
        end if

        ! Make ghost node
        mesh.node(node_up).ghost = 1
        mesh.node(node_dn).ghost = 1

        node_up = mesh.node(node_up).up
        node_dn = mesh.node(node_dn).dn
    end do
end subroutine Basepair_Make_Ghost_Node

! ---------------------------------------------------------------------------------------

! *--------->*        or        *<---------*
! node_cur   node_com           node_cur   node_com
! Increase edge length of the duplex to fill junctional gap
! Last updated on Fri 17 Mar 2017 by Hyungmin
subroutine Basepair_Increase_Edge(geom, bound, mesh, node_cur, node_com)
    type(geomType),  intent(inout) :: geom
    type(BoundType), intent(inout) :: bound
    type(MeshType),  intent(inout) :: mesh
    integer,         intent(in)    :: node_cur
    integer,         intent(in)    :: node_com

    double precision :: a, b, c, y, angle, len_side
    double precision :: length, pos(3), vec_in(3), vec_out(3)
    integer :: node_in, node_out, node_in_dn, node_out_up
    integer :: i, count, n_col_bottom
    logical :: b_increase

    b_increase = .false.

    ! ==================================================
    !
    ! *--------->*         or        *<---------*
    ! node_cur   node_com            node_cur   node_com
    !
    ! ==================================================
    ! Set direction, node_in and node_out
    if(mesh.node(node_cur).up == -1) then

        ! If the direction is "inward"
        node_in  = node_cur
        node_out = node_com
    else if(mesh.node(node_cur).dn == -1) then

        ! If the direction is "outward"
        node_in  = node_com
        node_out = node_cur
    end if

    // 두벡터가 이루는 각도계산 하는 공식 다시 체크
    // 두 포인트 사이의 거리와 공식으로 구해진 거리 비교
    // 한직선 사이에 있는지 체크 하는 것 해볼 것,, 두점이 한직선에 있는지...

    ! Set down and up ID
    node_in_dn  = mesh.node(node_in).dn
    node_out_up = mesh.node(node_out).up
    !
    !            @ angle
    !           ↗ ↘
    !          ↗   ↘
    !         *---->*         ---
    !     x  ↗   a   ↘         ↑        a : Ideal length determined
    !       ↗         ↘        ↓ ha     x : Variable to be determined (length)
    !  m1  *---------->* n1   ---      m1 : node_in
    !  y  ↗      b      ↘      ↑       n1 : node_out
    !    ↗               ↘     ↓ hb    m2 : node_in_down
    !   *-----------------*   ---      n2 : node_out_up
    ! m2         c         n2           y : para_dist_bp
    !                              ha, hb : Height of trapezodal
    !
    ! a  => Ideal length will be determined using 2nd cosine law
    ! b  => len_b, c => len_c
    ! y  => para_dist_bp
    ! ha => height_a, hb=> height_b
    ! x  => Length
    !
    ! Equations
    ! 1. b = Size_Vector(node_in-node_out)
    ! 2. c = Size_Vector(node_in_down-node_out_up)
    ! 3. ha/x = hb/y
    ! 4. x^2  = ha^2 + (1/2(b-a))^2
    ! 5. y^2  = hb^2 + (1/2(c-b))^2
    !
    !          *                     *
    !            ↘                 ↗
    ! node_in_down *             *    node_out_up
    !   vec_in(↘)    ↘         ↗       vec_out(↙)
    !                  *     *
    !           node_in     node_out

    ! Set inward and outward vector and find angle bewteen them
    vec_in(1:3)  = mesh.node(node_in).pos  - mesh.node(node_in_dn).pos
    vec_out(1:3) = mesh.node(node_out).pos - mesh.node(node_out_up).pos
    angle        = dacos(dot_product(vec_in, vec_out)/(Size_Vector(vec_in)*Size_Vector(vec_out)))

    ! 2nd cosine law to find the length, a
    len_side = para_rad_helix + para_gap_helix / 2.0d0
    a = dsqrt(2.0d0*len_side**2.0d0 - 2.0d0*len_side*len_side*dcos(pi-angle))

    ! Solving the above equation
    b = Size_Vector(mesh.node(node_in).pos    - mesh.node(node_out).pos)
    c = Size_Vector(mesh.node(node_in_dn).pos - mesh.node(node_out_up).pos)
    y = para_dist_bp

    ! If two nodes are close, skip this subroutine
    if(a > b) return

    ! Find final length
    length = dsqrt(((b-a)/2.0d0)**2.0d0 / (1.0d0-((y**2.0d0-((c-b)/2.0d0)**2.0d0)/y**2.0d0)))
    count  = dnint(length / dble(para_dist_bp))

    
    print *, length, count

    stop

    ! Loop for adding new nodes
    do i = 1, count - 1

        ! Add one basepair at the position indicating vector, return updated newly node ID
        call Basepair_Add_Basepair(geom, bound, mesh, node_in,  vec_in)
        call Basepair_Add_Basepair(geom, bound, mesh, node_out, vec_out)

        ! If the node was added, change junctional connectivity
        b_increase = .true.
    end do

    ! If the edge was modified, change junctional connectivity
    if(b_increase == .true.) then
        mesh.node(node_in).conn  = 1        ! Should be check
        mesh.node(node_out).conn = 1
    end if
end subroutine Basepair_Increase_Edge

! ---------------------------------------------------------------------------------------

! Add one basepair at the position indicating vector, vec, return updated newly node ID
! Last updated on Thursday 04 August 2016 by Hyungmin
subroutine Basepair_Add_Basepair(geom, bound, mesh, node, vec)
    type(GeomType),   intent(inout) :: geom
    type(BoundType),  intent(inout) :: bound
    type(MeshType),   intent(inout) :: mesh
    integer,          intent(inout) :: node
    double precision, intent(in)    :: vec(3)

    type(NodeType), allocatable, dimension(:) :: t_node
    type(EleType),  allocatable, dimension(:) :: t_ele

    integer :: i, j, k, croP

    ! Allocate temporal node data
    allocate(t_node(mesh.n_node))

    ! Copy from original data(mesh.node) to temporal data(t_node)
    call Mani_Copy_NodeType(mesh.node, t_node, mesh.n_node)

    ! Deallocate original node data
    deallocate(mesh.node)

    ! Increase the number of nodes
    mesh.n_node = mesh.n_node + 1

    ! Reallocate node data
    allocate(mesh.node(mesh.n_node))

    ! Copy from temporal data(t_node) to original data(mesh.node)
    call Mani_Copy_NodeType(t_node, mesh.node, mesh.n_node - 1)

    ! --------------------------------------------------
    !
    ! Set up new added node information
    !
    ! --------------------------------------------------
    ! Set node id
    mesh.node(mesh.n_node).id = mesh.n_node

    ! Set basepair ID and connectivity
    if(t_node(node).up == -1) then
        !
        ! If the direction of the node is "inward" to junction
        !           *--->*--->*--->*--->*  junction   0 (even)
        ! junction  *<---*<---*<---*<---*             1 (odd)
        ! bp ID     1    2    3    4    5
        !
        if(mod(t_node(node).sec, 2) == 0) then
            mesh.node(mesh.n_node).bp = t_node(node).bp + 1
        else
            mesh.node(mesh.n_node).bp = t_node(node).bp - 1
        end if

        mesh.node(mesh.n_node).up = -1
        mesh.node(mesh.n_node).dn = node
        mesh.node(node).up        = mesh.n_node

    else if(mesh.node(node).dn == -1) then
        !
        ! ! If the direction of the node is "outward" from junction
        ! junction  *--->*--->*--->*--->*             0 (even)
        !           *<---*<---*<---*<---*  junction   1 (odd)
        ! bp ID     1    2    3    4    5
        !
        if(mod(t_node(node).sec, 2) == 0) then
            mesh.node(mesh.n_node).bp = t_node(node).bp - 1
        else
            mesh.node(mesh.n_node).bp = t_node(node).bp + 1
        end if

        mesh.node(mesh.n_node).up = node
        mesh.node(mesh.n_node).dn = -1
        mesh.node(node).dn        = mesh.n_node
    else

        write(0, "(a$)"), "Error - Not junction : "
        write(0, "(a )"), "Basepair_Add_Node"
        stop
    end if

    ! Section, iniL and croL id
    mesh.node(mesh.n_node).sec  = t_node(node).sec
    mesh.node(mesh.n_node).iniL = t_node(node).iniL
    mesh.node(mesh.n_node).croL = t_node(node).croL

    ! Node connectivity for newly added node is derived from previous node
    mesh.node(mesh.n_node).conn = -1

    ! Set normal node for newly added node
    mesh.node(mesh.n_node).ghost = -1

    ! Node connectivity for previous node is assigned with -1 (no connection)
    mesh.node(node).conn = -1

    ! Set position and orientation vector
    do i = 1, 3
        mesh.node(mesh.n_node).pos(i)   = t_node(node).pos(i) + vec(i)
        mesh.node(mesh.n_node).ori(i,:) = t_node(node).ori(i,:)
    end do

    ! Deallocate temporal node data
    deallocate(t_node)

    ! --------------------------------------------------
    !
    ! Set up element connectivity
    !
    ! --------------------------------------------------
    ! Allocate temporal element data
    allocate(t_ele(mesh.n_ele))

    ! Copy from original data to temporal data
    call Mani_Copy_EleType(mesh.ele, t_ele, mesh.n_ele)

    ! Deallocate original data
    deallocate(mesh.ele)

    ! Increase the number of elements
    mesh.n_ele = mesh.n_ele + 1

    ! Reallocate original data
    allocate(mesh.ele(mesh.n_ele))

    ! Copy from temporal data to original data
    call Mani_Copy_EleType(t_ele, mesh.ele, mesh.n_ele - 1)

    ! Set added element connectivity
    mesh.ele(mesh.n_ele).cn(1) = node
    mesh.ele(mesh.n_ele).cn(2) = mesh.n_node

    ! Deallocate temporal element data
    deallocate(t_ele)

    ! --------------------------------------------------
    !
    ! Update junction information
    !
    ! --------------------------------------------------
    do i = 1, bound.n_junc
        do j = 1, geom.n_sec
            do k = 1, bound.junc(i).n_arm

                ! If the node is junctional node
                if(bound.junc(i).node(k, j) == node) then

                    ! Update newly added node
                    bound.junc(i).node(k, j) = mesh.n_node

                    ! Update cross-section point
                    croP = bound.junc(i).croP(k, j)
                    geom.croP(croP).pos(1:3) = mesh.node(mesh.n_node).pos(1:3)
                end if

                ! Update sectional connectivity
                if(bound.junc(i).conn((j-1)*bound.junc(i).n_arm+k, 1) == node) then
                    bound.junc(i).conn((j-1)*bound.junc(i).n_arm+k, 1) = mesh.n_node
                end if
                if(bound.junc(i).conn((j-1)*bound.junc(i).n_arm+k, 2) == node) then
                    bound.junc(i).conn((j-1)*bound.junc(i).n_arm+k, 2) = mesh.n_node
                end if
            end do
        end do
    end do

    ! Update newly added node number
    node = mesh.n_node
end subroutine Basepair_Add_Basepair

! ---------------------------------------------------------------------------------------

! Delete ghost node from node data
! Last updated on Thursday 28 July 2016 by Hyungmin
subroutine Basepair_Delete_Ghost_Node(geom, bound, mesh)
    type(GeomType),  intent(inout) :: geom
    type(BoundType), intent(inout) :: bound
    type(MeshType),  intent(inout) :: mesh

    integer :: str_node, end_node, count, min, max, size, croP
    integer :: i, j, k, ii, jj, kk, up, dn
    logical :: b_up, b_dn

    ! Print progress
    do i = 0, 11, 11
        call Space(i, 6)
        write(i, "(a )"), "4.5. Delete ghost node to avoid crash"
        call Space(i, 11)
        write(i, "(a)"), "* The number of nodes before modfication : "//trim(adjustl(Int2Str(mesh.n_node)))
    end do

    ! Loop for junctional nodes
    do i = 1, bound.n_junc

        ! Print progress bar
        call Mani_Progress_Bar(i, bound.n_junc)

        do j = 1, bound.junc(i).n_arm
            do k = 1, geom.n_sec

                ! Find junction node
                str_node = bound.junc(i).node(j, k)
                end_node = str_node
                count    = 0

                ! Check ghost node
                if(mesh.node(str_node).ghost == 1) then

                    ! Set direction of current node
                    count = 1
                    b_up = .false.
                    b_up = .false.
                    if(mesh.node(str_node).dn == -1) then
                        b_up = .true.
                        up   = str_node
                    else
                        b_dn = .true.
                        dn   = str_node
                    end if

                    ! --------------------------------------------------
                    !
                    ! Find next ghost node depending on direction
                    ! Find min and max node ID to be deleted
                    !
                    ! --------------------------------------------------
                    do

                        if(b_up == .true.) then

                            ! If the direction is going to upward
                            up = mesh.node(up).up

                            if(mesh.node(up).ghost == 1) then
                                count = count + 1
                            else
                                ! The end node is previous visited ghost node
                                end_node = mesh.node(mesh.node(up).id).dn

                                ! Set connectivity for current visiting node
                                mesh.node(up).dn         = -1
                                mesh.node(up).conn       = 4
                                bound.junc(i).node(j, k) = mesh.node(up).id

                                ! Set cross-sectional point
                                croP = bound.junc(i).croP(j, k)
                                geom.croP(croP).pos(1:3) = mesh.node(up).pos(1:3)

                                ! Set junctional connectivity
                                do ii = 1, bound.n_junc
                                    do jj = 1, geom.n_sec*bound.junc(ii).n_arm

                                        if(bound.junc(ii).conn(jj, 1) == str_node) then
                                            bound.junc(ii).conn(jj, 1) = mesh.node(up).id
                                        end if

                                        if(bound.junc(ii).conn(jj, 2) == str_node) then
                                            bound.junc(ii).conn(jj, 2) = mesh.node(up).id
                                        end if
                                    end do
                                end do

                                ! Exit loop
                                exit
                            end if
                        else if(b_dn == .true.) then

                            ! If the direction is going to downward
                            dn = mesh.node(dn).dn

                            if(mesh.node(dn).ghost == 1) then
                                count = count + 1
                            else
                                ! The end node is previous visited ghost node
                                end_node = mesh.node(mesh.node(dn).id).up

                                ! Set connectivity for current visiting node
                                mesh.node(dn).up         = -1
                                mesh.node(dn).conn       = 4
                                bound.junc(i).node(j, k) = mesh.node(dn).id

                                ! Set cross-sectional point
                                croP = bound.junc(i).croP(j, k)
                                geom.croP(croP).pos(1:3) = mesh.node(dn).pos(1:3)

                                ! Set junctional connectivity
                                do ii = 1, bound.n_junc
                                    do jj = 1, geom.n_sec*bound.junc(ii).n_arm

                                        if(bound.junc(ii).conn(jj, 1) == str_node) then
                                            bound.junc(ii).conn(jj, 1) = mesh.node(dn).id
                                        end if

                                        if(bound.junc(ii).conn(jj, 2) == str_node) then
                                            bound.junc(ii).conn(jj, 2) = mesh.node(dn).id
                                        end if
                                    end do
                                end do

                                ! Exit loop
                                exit
                            end if
                        end if
                    end do

                    ! --------------------------------------------------
                    !
                    ! Delete nodes from min ID to max ID
                    !
                    ! --------------------------------------------------

                    if(str_node > end_node) then
                        min = end_node
                        max = str_node
                    else
                        min = str_node
                        max = end_node
                    end if
                    size = max - min + 1

                    ! Delete node from min to max ID
                    call Basepair_Delete_Nodes(mesh, min, max)

                    ! Reset junction connectivity
                    do ii = 1, bound.n_junc

                        do jj = 1, bound.junc(ii).n_arm
                            do kk = 1, geom.n_sec

                                ! Reset node connectivity
                                if(bound.junc(ii).node(jj, kk) > max) then
                                    bound.junc(ii).node(jj, kk) = bound.junc(ii).node(jj, kk) - size
                                end if
                            end do
                        end do

                        do jj = 1, geom.n_sec*bound.junc(ii).n_arm

                            ! Reset junction connectivity
                            if(bound.junc(ii).conn(jj, 1) > max) then
                                bound.junc(ii).conn(jj, 1) = bound.junc(ii).conn(jj, 1) - size
                            end if

                            if(bound.junc(ii).conn(jj, 2) > max) then
                                bound.junc(ii).conn(jj, 2) = bound.junc(ii).conn(jj, 2) - size
                            end if
                        end do
                    end do
                end if
            end do
        end do
    end do

    ! Print progress
    do i = 0, 11, 11
        call Space(i, 11)
        write(i, "(a)"), "* The number of nodes after modfication  : "//trim(adjustl(Int2Str(mesh.n_node)))
    end do
    write(0, "(a)"); write(11, "(a)")
end subroutine Basepair_Delete_Ghost_Node

! ---------------------------------------------------------------------------------------

! Delete node from min to max ID
! Last updated on Thursday 28 July 2016 by Hyungmin
subroutine Basepair_Delete_Nodes(mesh, min, max)
    type(MeshType), intent(inout) :: mesh
    integer,        intent(in)    :: min
    integer,        intent(in)    :: max
    
    type(NodeType), allocatable, dimension(:) :: t_node
    type(EleType),  allocatable, dimension(:) :: t_ele

    integer :: i, j, n_delete, count

    n_delete = max - min + 1

    ! --------------------------------------------------
    !
    ! Modify node data
    !
    ! --------------------------------------------------
    ! Allocate temporal node data to store previous data
    allocate(t_node(mesh.n_node))

    ! Copy data from node to t_node
    do i = 1, mesh.n_node
        t_node(i).id    = mesh.node(i).id       ! Node id
        t_node(i).bp    = mesh.node(i).bp       ! Base pair id
        t_node(i).up    = mesh.node(i).up       ! Upward id
        t_node(i).dn    = mesh.node(i).dn       ! Downward id
        t_node(i).sec   = mesh.node(i).sec      ! Section id
        t_node(i).iniL  = mesh.node(i).iniL     ! Initial line
        t_node(i).croL  = mesh.node(i).croL     ! Sectional line
        t_node(i).conn  = mesh.node(i).conn     ! Connection type
        t_node(i).ghost = mesh.node(i).ghost    ! Ghost node type

        ! Position and orientation vector
        do j = 1, 3
            t_node(i).pos(j)      = mesh.node(i).pos(j)
            t_node(i).ori(j, 1:3) = mesh.node(i).ori(j, 1:3)
        end do
    end do

    ! Deallocate original node data
    deallocate(mesh.node)

    ! Decrease the number of nodes
    mesh.n_node = mesh.n_node - n_delete

    ! Reallocate node data
    allocate(mesh.node(mesh.n_node))

    count = 0
    do i = 1, mesh.n_node

        if(i == min) count = n_delete

        mesh.node(i).id    = t_node(i+count).id         ! Node ID
        mesh.node(i).bp    = t_node(i+count).bp         ! Base pair ID
        mesh.node(i).up    = t_node(i+count).up         ! Upward ID
        mesh.node(i).dn    = t_node(i+count).dn         ! Downward ID
        mesh.node(i).sec   = t_node(i+count).sec        ! Section ID
        mesh.node(i).iniL  = t_node(i+count).iniL       ! Initial edge
        mesh.node(i).croL  = t_node(i+count).croL       ! Sectional edge
        mesh.node(i).conn  = t_node(i+count).conn       ! Connection type
        mesh.node(i).ghost = t_node(i+count).ghost      ! Ghost node type

        do j = 1, 3
            mesh.node(i).pos(j)      = t_node(i+count).pos(j)
            mesh.node(i).ori(j, 1:3) = t_node(i+count).ori(j, 1:3)
        end do

        if(mesh.node(i).id > max) mesh.node(i).id = mesh.node(i).id - n_delete
        if(mesh.node(i).up > max) mesh.node(i).up = mesh.node(i).up - n_delete
        if(mesh.node(i).dn > max) mesh.node(i).dn = mesh.node(i).dn - n_delete
    end do

    ! Deallocate temporal node data
    deallocate(t_node)

    ! --------------------------------------------------
    !
    ! Modify element connectivity
    !
    ! --------------------------------------------------
    allocate(t_ele(mesh.n_ele))

    ! Copy from original data to temporal data
    do i = 1, mesh.n_ele
        t_ele(i).cn(1:2) = mesh.ele(i).cn(1:2)
    end do

    ! Deallocate original data
    deallocate(mesh.ele)

    ! Increase the number of elements
    mesh.n_ele = mesh.n_ele - n_delete

    ! Reallocate original data
    allocate(mesh.ele(mesh.n_ele))

    ! Copy from temporal data to original data
    count = 0
    do i = 1, mesh.n_ele + n_delete

        if(t_ele(i).cn(1) >= min .and. t_ele(i).cn(1) <= max) cycle
        if(t_ele(i).cn(2) >= min .and. t_ele(i).cn(2) <= max) cycle

        count = count + 1
        mesh.ele(count).cn(1:2) = t_ele(i).cn(1:2)

        if(mesh.ele(count).cn(1) > max) mesh.ele(count).cn(1) = mesh.ele(count).cn(1) - n_delete
        if(mesh.ele(count).cn(2) > max) mesh.ele(count).cn(2) = mesh.ele(count).cn(2) - n_delete
    end do

    ! Deallocate temporal data
    deallocate(t_ele)
end subroutine Basepair_Delete_Nodes

! ---------------------------------------------------------------------------------------

! Make stick end with one additional node at inward direction from vertex
! Last updated on Thuesday 17 August 2016 by Hyungmin
subroutine Basepair_Make_Sticky_End(geom, bound, mesh)
    type(GeomType),  intent(inout) :: geom
    type(BoundType), intent(inout) :: bound
    type(MeshType),  intent(inout) :: mesh

    type(NodeType), allocatable, dimension(:) :: t_node
    type(EleType),  allocatable, dimension(:) :: t_ele

    double precision :: pos(3), vec(3)
    integer :: i, j, k, ii, jj, sec, node, pre, croP, pre_n_node, pre_n_ele

    ! Print progress
    do i = 0, 11, 11
        call Space(i, 6)
        write(i, "(a)"), "4.6. Make sticky-end at 5'- end node near the junction"
    end do

    ! This modification is only for strucutres based on honeycomb lattice
    if(geom.sec.types == "square") then
        write(0, "(a)"); write(11, "(a)")
        return
    end if
    !if(geom.sec.types == "honeycomb") return

    pre_n_node = mesh.n_node
    pre_n_ele  = mesh.n_ele

    ! Loop for all junctions
    do i = 1, bound.n_junc

        ! Print progress bar
        call Mani_Progress_Bar(i, bound.n_junc)

        ! Print progress
        write(11, "(i20, a$)"), i, " th junc, # of arms : "
        write(11, "(i4,  a$)"), bound.junc(i).n_arm, " --> Added node # : "

        do j = 1, bound.junc(i).n_arm
            do k = 1, geom.n_sec

                ! Current node at the junction
                node = bound.junc(i).node(j, k)
                sec  = mesh.node(node).sec

                ! If modified self connection, skip this loop
                if(mesh.node(node).conn == 4 .and. para_sticky_self == "off") cycle

                ! If the node is inward direction from vertex
                if(mesh.node(node).dn == -1) then
                    !
                    !          1      2      3      4
                    !       #  *----->*----->*----->*    : +z-direction
                    !         node    up
                    !    new base
                    !          1      2      3      4    : base ID
                    ! Add one base at the 5'-end of junction, which has -1 on down ID
                    ! Check sticky-end for self connection on the cross-section
                    if(para_sticky_self == "off") then

                        ! For non-sticky for self connection
                        if(geom.sec.conn(sec+1) /= -1 .and. mod(mesh.node(node).sec, 2) == 0) cycle
                    end if

                    ! Allocate temporal data
                    call move_alloc(mesh.node, t_node)
                    call move_alloc(mesh.ele,  t_ele)

                    ! Increase # of nodes and elements
                    mesh.n_node = mesh.n_node + 1
                    mesh.n_ele  = mesh.n_ele  + 1

                    allocate(mesh.node(mesh.n_node))
                    allocate(mesh.ele(mesh.n_ele))

                    ! Copy nodes and elements from temporal data
                    call Mani_Copy_NodeType(t_node, mesh.node, mesh.n_node - 1)
                    call Mani_Copy_EleType (t_ele,  mesh.ele,  mesh.n_ele  - 1)

                    ! Set new added node
                    ! New added node ID - mesh.n_node, previous node ID : node
                    mesh.node(mesh.n_node).id = mesh.n_node

                    if(mod(mesh.node(node).sec, 2) == 0) then
                        mesh.node(mesh.n_node).bp = t_node(node).bp - 1
                    else
                        mesh.node(mesh.n_node).bp = t_node(node).bp + 1
                    end if

                    mesh.node(mesh.n_node).up = t_node(node).id
                    mesh.node(mesh.n_node).dn = -1

                    ! Update previous node connectivity
                    mesh.node(node).dn = mesh.node(mesh.n_node).id

                    ! Find position vector for new added node
                    pre = mesh.node(node).up

                else if(mesh.node(node).up == -1 .and. geom.sec.conn(sec + 1) /= -1 .and. mod(mesh.node(node).sec, 2) == 0 ) then
                    !
                    !          1      2      3      4
                    !          *----->*----->*----->*  # : +z-direction
                    !         node    up
                    !                               new base
                    !          1      2      3      4    : base ID
                    ! For all sticky-end for 5'-end nodes
                    if(para_sticky_self /= "off") cycle

                    ! Allocate temporal data
                    call move_alloc(mesh.node, t_node)
                    call move_alloc(mesh.ele,  t_ele)

                    ! Increase # of nodes and elements
                    mesh.n_node = mesh.n_node + 1
                    mesh.n_ele  = mesh.n_ele  + 1

                    allocate(mesh.node(mesh.n_node))
                    allocate(mesh.ele(mesh.n_ele))

                    ! Copy nodes and elements from temporal data
                    call Mani_Copy_NodeType(t_node, mesh.node, mesh.n_node - 1)
                    call Mani_Copy_EleType (t_ele,  mesh.ele,  mesh.n_ele  - 1)

                    ! Set new added node
                    ! New added node ID - mesh.n_node, previous node ID : node
                    mesh.node(mesh.n_node).id = mesh.n_node
                    mesh.node(mesh.n_node).bp = t_node(node).bp + 1
                    mesh.node(mesh.n_node).up = -1
                    mesh.node(mesh.n_node).dn = t_node(node).id

                    ! Update previous node connectivity
                    mesh.node(node).up = mesh.node(mesh.n_node).id

                    ! Find position vector for new added node
                    pre = mesh.node(node).dn
                else
                    cycle
                end if

                mesh.node(mesh.n_node).sec   = t_node(node).sec
                mesh.node(mesh.n_node).iniL  = t_node(node).iniL
                mesh.node(mesh.n_node).croL  = t_node(node).croL
                mesh.node(mesh.n_node).conn  = t_node(node).conn
                mesh.node(mesh.n_node).ghost = t_node(node).ghost

                pos(1:3) = t_node(node).pos + (t_node(node).pos - t_node(pre).pos) &
                    / Size_Vector(t_node(node).pos - t_node(pre).pos) * dble(para_dist_bp)
                mesh.node(mesh.n_node).pos(1:3) = pos(1:3)

                ! Set element connectivity for the newly added node
                mesh.ele(mesh.n_ele).cn(1) = node
                mesh.ele(mesh.n_ele).cn(2) = mesh.n_node

                ! Deallocate memory
                deallocate(t_node)
                deallocate(t_ele)

                ! -------------------------------------------------------
                !
                ! Update all junction connectivity
                !
                ! -------------------------------------------------------
                ! Update junction node connectivity
                bound.junc(i).node(j, k) = mesh.n_node

                ! Update sectional connection information at the junction
                do ii = 1, bound.n_junc
                    do jj = 1, bound.junc(ii).n_arm * geom.n_sec
                        if(bound.junc(ii).conn(jj, 1) == node) bound.junc(ii).conn(jj, 1) = mesh.n_node
                        if(bound.junc(ii).conn(jj, 2) == node) bound.junc(ii).conn(jj, 2) = mesh.n_node
                    end do
                end do

                ! Update sectional point
                croP = bound.junc(i).croP(j, k)
                geom.croP(croP).pos(1:3) = mesh.node(mesh.n_node).pos(1:3)

                ! Print progress
                write(11, "(i7, a, i7, a$)"), node, " ->", mesh.n_node, ", "
            end do
        end do
        write(11, "(a)")
    end do

    ! Print progress
    do i = 0, 11, 11
        call Space(i, 11)
        write(i, "(a)"), "* The number of newly added sticky bases : "//&
            trim(adjustl(Int2Str(mesh.n_node - pre_n_node)))
        call Space(i, 11)
        write(i, "(a)"), "* The number of newly added elements     : "//&
            trim(adjustl(Int2Str(mesh.n_ele - pre_n_ele)))
    end do

    ! Print modified junction connectivity
    do i = 1, bound.n_junc

        write (11, "(i20, a, i2, a$)"), i, " th junc : ", bound.junc(i).n_arm, "-arms --> node # : "
        do j = 1, geom.n_sec
            do k = 1, bound.junc(i).n_arm
                write (11, "(i7$)"), bound.junc(i).node(k, j)

                ! Check end node that should be -1
                if(mesh.node(bound.junc(i).node(k, j)).up /= -1 .and. mesh.node(bound.junc(i).node(k, j)).dn /= -1) then
                    write(0, "(a$)"), "Error - Not negative value : "
                    write(0, "(a )"), "Basepair_Make_Sticky_End"
                    stop
                end if
            end do
            write (11, "(a$)"), " ///// "
        end do
        write (11, "(a)")
    end do

    write(0, "(a)"); write(11, "(a)")
end subroutine Basepair_Make_Sticky_End

! ---------------------------------------------------------------------------------------

! Write Chimera FE mesh
! Last updated on Monday 15 Feb 2016 by Hyungmin
subroutine Basepair_Chimera_Mesh(prob, geom, mesh)
    type(ProbType), intent(in) :: prob
    type(GeomType), intent(in) :: geom
    type(MeshType), intent(in) :: mesh

    double precision :: pos_1(3), pos_2(3), pos_c(3)
    double precision :: pos_a(3), pos_b(3), length
    integer :: i, j, iter
    logical :: b_mod, b_axis
    character(200) :: path

    if(para_write_503 == .false.) return

    ! Set option
    b_axis = para_chimera_axis
    b_mod  = para_chimera_503_mod

    path = trim(prob.path_work1)//trim(prob.name_file)
    open(unit=503, file=trim(path)//"_mesh.bild", form="formatted")

    ! Write finite nodes(basepair)
    do i = 1, mesh.n_node

        if(mesh.node(i).ghost == 1) cycle

        write(503, "(a     )"), ".color orange"
        write(503, "(a$    )"), ".sphere "
        write(503, "(3f9.3$)"), mesh.node(i).pos(1:3)
        write(503, "(1f9.3 )"), 0.15d0
    end do

    ! Write finite element(basepair connectivity)
    do i = 1, mesh.n_ele
        pos_1(1:3) = mesh.node(mesh.ele(i).cn(1)).pos(1:3)
        pos_2(1:3) = mesh.node(mesh.ele(i).cn(2)).pos(1:3)

        write(503, "(a     )"), ".color blue"
        write(503, "(a$    )"), ".cylinder "
        write(503, "(3f9.3$)"), pos_1(1:3)
        write(503, "(3f9.3$)"), pos_2(1:3)
        write(503, "(1f9.3 )"), 0.08d0
    end do

    ! Draw modified geometry
    if(b_mod == .true.) then

        ! Draw modified lines
        do i = 1, geom.n_iniL
            pos_1(1:3) = geom.modP(geom.iniL(i).poi(1)).pos(1:3)
            pos_2(1:3) = geom.modP(geom.iniL(i).poi(2)).pos(1:3)
            pos_c(1:3) = Normalize_Vector(pos_2(1:3) - pos_1(1:3))

            length = Size_Vector(pos_2(1:3) - pos_1(1:3))
            iter   = length / 2

            do j = 1, iter * 2
                if(mod(j, 2) == 1) then
                    pos_a(1:3) = pos_1(1:3) + dble(j-1) * pos_c(1:3)
                    pos_b(1:3) = pos_1(1:3) + dble(j)   * pos_c(1:3)

                    write(503, "(a     )"), ".color dark green"
                    write(503, "(a$    )"), ".cylinder "
                    write(503, "(3f9.3$)"), pos_a(1:3)
                    write(503, "(3f9.3$)"), pos_b(1:3)
                    write(503, "(1f9.3 )"), 0.1d0
                end if
            end do
        end do

        ! Draw modified points
        do i = 1, geom.n_modP
            write(503, "(a     )"), ".color dark green"
            write(503, "(a$    )"), ".sphere "
            write(503, "(3f9.3$)"), geom.modP(i).pos(1:3)
            write(503, "(1f9.3 )"), 0.2d0
        end do
    end if

    ! Write global axis
    if(b_axis == .true.) then
        write(503, "(a)"), ".translate 0.0 0.0 0.0"
        write(503, "(a)"), ".scale 0.5"
        write(503, "(a)"), ".color grey"
        write(503, "(a)"), ".sphere 0 0 0 0.5"      ! Center
        write(503, "(a)"), ".color red"             ! x-axis
        write(503, "(a)"), ".arrow 0 0 0 4 0 0 "
        write(503, "(a)"), ".color blue"            ! y-axis
        write(503, "(a)"), ".arrow 0 0 0 0 4 0 "
        write(503, "(a)"), ".color yellow"          ! z-axis
        write(503, "(a)"), ".arrow 0 0 0 0 0 4 "
    end if

    close(unit=503)
end subroutine Basepair_Chimera_Mesh

! ---------------------------------------------------------------------------------------

! Write cross-sectional geometry
! Last updated on Saturday 16 July 2016 by Hyungmin
subroutine Basepair_Chimera_Cross_Geometry(prob, geom)
    type(ProbType), intent(in)    :: prob
    type(GeomType), intent(inout) :: geom

    double precision :: pos_1(3), pos_2(3), pos_c(3), pos_a(3), pos_b(3)
    double precision :: length, t1(3), t2(3), t3(3)
    integer :: i, j, iter, nbp
    logical :: f_axis, f_info
    character(200) :: path

    if(para_write_504 == .false.) return

    ! Set option
    f_axis = para_chimera_axis
    f_info = para_chimera_504_info

    path = trim(prob.path_work1)//trim(prob.name_file)
    open(unit=504, file=trim(path)//"_cross_geo_mod.bild", form="formatted")

    ! Write cross-sectional points
    write(504, "(a)"), ".color red"
    do i = 1, geom.n_croP

        write(504, "(a$    )"), ".sphere "
        write(504, "(3f9.3$)"), geom.croP(i).pos(1:3)
        write(504, "(1f9.3 )"), 0.35d0
    end do

    ! Write cross-sectional edges
    write(504, "(a)"), ".color dark green"
    do i = 1, geom.n_croL

        pos_1(1:3) = geom.croP(geom.croL(i).poi(1)).pos(1:3)
        pos_2(1:3) = geom.croP(geom.croL(i).poi(2)).pos(1:3)

        write(504, "(a$   )"), ".cylinder "
        write(504, "(7f9.3)"), pos_1(1:3), pos_2(1:3), 0.15d0
    end do

    ! Write information
    if(f_info == .true.) then

        ! Write modified points
        write(504, "(a)"), ".color dark green"
        do i = 1, geom.n_modP
            write(504, "(a$    )"), ".sphere "
            write(504, "(3f9.3$)"), geom.modP(i).pos(1:3)
            write(504, "(1f9.3 )"), 0.3d0
        end do

        ! Write modified edges
        do i = 1, geom.n_iniL
            pos_1(1:3) = geom.modP(geom.iniL(i).poi(1)).pos(1:3)
            pos_2(1:3) = geom.modP(geom.iniL(i).poi(2)).pos(1:3)
            pos_c(1:3) = Normalize_Vector(pos_2(1:3) - pos_1(1:3))

            length = Size_Vector(pos_2(1:3) - pos_1(1:3))
            iter   = length / 2

            do j = 1, iter * 2
                if(mod(j, 2) == 1) then
                    pos_a(1:3) = pos_1(1:3) + dble(j-1) * pos_c(1:3)
                    pos_b(1:3) = pos_1(1:3) + dble(j)   * pos_c(1:3)

                    write(504, "(a$    )"), ".cylinder "
                    write(504, "(3f9.3$)"), pos_a(1:3)
                    write(504, "(3f9.3$)"), pos_b(1:3)
                    write(504, "(1f9.3 )"), 0.1d0
                end if
            end do
        end do

        ! Information on edge number
        do i = 1, geom.n_croL
            pos_1(1:3) = geom.croP(geom.croL(i).poi(1)).pos(1:3)
            pos_2(1:3) = geom.croP(geom.croL(i).poi(2)).pos(1:3)
            pos_c(1:3) = (pos_1(1:3) + pos_2(1:3)) / 2.0d0

            write(504, "(a$    )"), ".cmov "
            write(504, "(3f9.3 )"), pos_c(1:3) + 0.4d0
            write(504, "(a     )"), ".color dark green"
            write(504, "(a     )"), ".font Helvetica 12 bold"
            write(504, "(i7, a$)"), i,                "("
            write(504, "(i3, a )"), geom.croL(i).sec, ")"
        end do

        ! Local coordinate system on cross-sectional edges
        do i = 1, geom.n_croL
            pos_1(1:3) = geom.croP(geom.croL(i).poi(1)).pos(1:3)
            pos_2(1:3) = geom.croP(geom.croL(i).poi(2)).pos(1:3)
            pos_c(1:3) = (pos_1(1:3) + pos_2(1:3)) / 2.0d0

            t1(1:3) = geom.croL(i).t(1, 1:3)
            t2(1:3) = geom.croL(i).t(2, 1:3)
            t3(1:3) = geom.croL(i).t(3, 1:3)

            write(504, "(a     )"), ".color red"    ! x-axis
            write(504, "(a$    )"), ".arrow "
            write(504, "(3f8.2$)"), pos_c(1:3)
            write(504, "(3f8.2$)"), pos_c(1:3) + t1(1:3) * 1.5d0
            write(504, "(3f8.2 )"), 0.18d0, 0.36d0, 0.6d0

            write(504, "(a     )"), ".color blue"   ! y-axis
            write(504, "(a$    )"), ".arrow "
            write(504, "(3f8.2$)"), pos_c(1:3)
            write(504, "(3f8.2$)"), pos_c(1:3) + t2(1:3) * 1.2d0
            write(504, "(3f8.2 )"), 0.15d0, 0.3d0, 0.6d0

            write(504, "(a     )"), ".color yellow" ! z-axis
            write(504, "(a$    )"), ".arrow "
            write(504, "(3f8.2$)"), pos_c(1:3)
            write(504, "(3f8.2$)"), pos_c(1:3) + t3(1:3) * 1.2d0
            write(504, "(3f8.2 )"), 0.15d0, 0.3d0, 0.6d0
        end do
    end if

    ! Write global axis
    if(f_axis == .true.) then
        write(504, "(a)"), ".translate 0.0 0.0 0.0"
        write(504, "(a)"), ".scale 0.5"
        write(504, "(a)"), ".color grey"
        write(504, "(a)"), ".sphere 0 0 0 0.5"      ! Center
        write(504, "(a)"), ".color red"             ! x-axis
        write(504, "(a)"), ".arrow 0 0 0 4 0 0 "
        write(504, "(a)"), ".color blue"            ! y-axis
        write(504, "(a)"), ".arrow 0 0 0 0 4 0 "
        write(504, "(a)"), ".color yellow"          ! z-axis
        write(504, "(a)"), ".arrow 0 0 0 0 0 4 "
    end if
    close(unit=504)

    ! ---------------------------------------------
    !
    ! Write the file for Tecplot
    !
    ! ---------------------------------------------
    if(para_output_Tecplot == "off") return

    path = trim(prob.path_work1)//"Tecplot\"//trim(prob.name_file)
    open(unit=504, file=trim(path)//"_cross_geo_mod.dat", form="formatted")

    write(504, "(a )"), 'TITLE = "'//trim(prob.name_file)//'"'
    write(504, "(a )"), 'VARIABLES = "X", "Y", "Z", "weight"'
    write(504, "(a$)"), 'ZONE F = FEPOINT'
    write(504, "(a$)"), ', N='//trim(adjustl(Int2Str(geom.n_croP)))
    write(504, "(a$)"), ', E='//trim(adjustl(Int2Str(geom.n_croL)))
    write(504, "(a )"), ', ET=LINESEG'

    ! Write points
    do i = 1, geom.n_croP
        write(504, "(3f9.3$)"), geom.croP(i).pos(1:3)
        write(504, "(1f9.3 )"), 1.0d0
    end do

    ! Write edges
    do i = 1, geom.n_croL
        write(504, "(1i7$)"), geom.croL(i).poi(1)
        write(504, "(1i7 )"), geom.croL(i).poi(2)
    end do

    close(unit=504)
end subroutine Basepair_Chimera_Cross_Geometry

! ---------------------------------------------------------------------------------------

! Write edge length
! Last updated on Friday 23 September 2016 by Hyungmin
subroutine Basepair_Write_Edge_Length(prob, geom)
    type(ProbType), intent(in)    :: prob
    type(GeomType), intent(inout) :: geom

    integer, allocatable, dimension(:) :: num_bp
    integer, allocatable, dimension(:) :: num_count

    double precision :: length
    integer :: i, j, poi_1, poi_2, n_bp, n_numbp, tot_bp
    integer :: max_edge, min_edge
    logical :: b_add
    character(200) :: path

    if(para_write_505 == .false.) return

    ! Allocate num_bp and num_count memory
    allocate(num_bp(geom.n_croL))
    allocate(num_count(geom.n_croL))

    path = trim(prob.path_work1)
    open(unit=505, file=trim(path)//"edge_length.txt", form="formatted")

    call space(505, 15)
    write(505, "(a)"), "Cros line         Edge length(bp)"

    ! The number of base pairs on each edge
    n_numbp = 0
    tot_bp  = 0
    do i = 1, size(geom.croL)
        poi_1  = geom.croL(i).poi(1)
        poi_2  = geom.croL(i).poi(2)
        length = Size_Vector(geom.croP(poi_1).pos - geom.croP(poi_2).pos)
        n_bp   = nint(length / para_dist_bp) + 1
        tot_bp = tot_bp + n_bp

        write(505, "(2i20)"), i, n_bp

        ! Save the number if it doesn't exist
        b_add = .true.
        do j = 1, n_numbp
            if(num_bp(j) == n_bp) then
                num_count(j) = num_count(j) + 1
                b_add = .false.
                exit
            end if
        end do

        ! Add new numbp data
        if(b_add == .true.) then
            num_bp(j)    = n_bp
            num_count(j) = 1
            n_numbp      = n_numbp + 1
        end if
    end do

    ! Sort the vector ascending order
    call Sort2(num_bp, num_count, n_numbp)

    write(505, "(a)")
    call space(505, 12)
    write(505, "(a)"), "Edge length(bp)      # of edges"

    ! Write edge length and count
    max_edge = num_bp(1)
    min_edge = num_bp(1)
    do i = 1, n_numbp
        write(505, "(2i20)"), num_bp(i), num_count(i)

        if(max_edge < num_bp(i)) max_edge = num_bp(i)
        if(min_edge > num_bp(i)) min_edge = num_bp(i)
    end do
    geom.min_edge_length = min_edge
    geom.max_edge_length = max_edge

    ! print progress
    do i = 0, 11, 11
        call Space(i, 6)
        write(i, "(a)"), "4.7. The Edge length"
        call Space(i, 11)
        write(i, "(a)"), "* The minimum edge length                : "//trim(adjustl(Int2Str(min_edge)))//" bp"
        call Space(i, 11)
        write(i, "(a)"), "* The maximum edge length                : "//trim(adjustl(Int2Str(max_edge)))//" bp"
        call Space(i, 11)
        write(i, "(a)"), "* # of edges that have different length  : "//trim(adjustl(Int2Str(n_numbp)))
        do j = 1, n_numbp
            call Space(i, 16)
            write(i, "(a, i4, a, i4)"), "+ ", num_bp(j), " bp edge length -> # : ", num_count(j)
        end do
    end do

    ! Sort the vector ascending order
    !call Sort2(num_count, num_bp, n_numbp)

    ! print progress
    !do i = 0, 11, 11
    !    call Space(i, 11)
    !    write(i, "(a$ )"), "* The minimum count, # of BPs    : "
    !    write(i, "(2i7)"), num_count(1), num_bp(1)
    !    call Space(i, 11)
    !    write(i, "(a$ )"), "* The maximum count, # of BPs    : "
    !    write(i, "(2i7)"), num_count(n_numbp), num_bp(n_numbp)
    !end do

    ! deallocate num_bp and num_count memory
    deallocate(num_bp)
    deallocate(num_count)

    close(unit=505)
end subroutine Basepair_Write_Edge_Length

! ---------------------------------------------------------------------------------------

end module Basepair