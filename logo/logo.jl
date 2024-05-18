using Luxor
using Luxor.Colors
using LinearAlgebra

let

Drawing(600, 600, joinpath(@__DIR__, "logo.png"))
origin()
# background("white")

center = Point(gettranslation())

jl_radius = 75
trio_radius = 105
center_gray = Point(-120,-100)
center_patch = Point(120,150)
gray_pt_red, gray_pt_purple, gray_pt_green = ngon(center_gray, trio_radius,
                                                  3, -π/2, vertices=true)
patch_pt_red, patch_pt_purple, patch_pt_green = ngon(center_patch, trio_radius,
                                                     3, -π/2, vertices=true)

setcolor(Luxor.julia_purple)
circle(gray_pt_purple, jl_radius, action = :fill)
setcolor(Luxor.julia_red)
circle(gray_pt_red, jl_radius, action = :fill)
setcolor(Luxor.julia_green)
circle(gray_pt_green, jl_radius, action = :fill)

# green patched circle
@layer begin
    setcolor(Luxor.julia_green)
    p = center+patch_pt_green
    origin(p)
    circle(O, jl_radius, action = :fill)
    circle(O, jl_radius, action = :clip)
    lw, N = 10, 10
    dir = Point(0,1)
    setcolor(sethue("darkgreen")...,0.6)
    rotate(-π*2/5)
    for i = -N:N
      box(O+dir*lw*2*i, 400, lw, action=:fill)
    end
    setcolor(sethue("yellow2")...,0.2)
    rotate(π/2)
    for i = -N:N
      box(O+dir*lw*2*i, 400, lw, action=:fill)
    end
    circle(O, jl_radius, action = :clip)
end

# red patched circle
@layer begin
    setcolor(Luxor.julia_red)
    p = center+patch_pt_red
    origin(p)
    circle(O, jl_radius, action = :fill)
    circle(O, jl_radius, action = :clip)
    w, h = 20, 20
    dx, dy = Point(w,0), Point(0,h)
    Nx, Ny = 10, 10
    setcolor(sethue("red4")...,0.5)
    rotate(-π*3/5)
    for ix = -Nx:Nx, iy=-Ny:Ny
      isodd(ix) && isodd(iy) && continue
      iseven(ix) && iseven(iy) && continue
      box(O+dx*ix+dy*iy, w, h, action=:fill)
    end
    circle(O, jl_radius, action = :clip)
end

# purple patched circle
@layer begin
    setcolor(Luxor.julia_purple)
    p = center+patch_pt_purple
    origin(p)
    circle(O, jl_radius, action = :fill)
    circle(O, jl_radius, action = :clip)
    dx, dy = Point(25,0), Point(0,25)
    Nx, Ny = 10, 10
    setcolor(sethue("purple4")...,0.5)
    rotate(-π*6/5)
    for ix = -Nx:Nx, iy = -Ny:Ny
      isodd(ix) && isodd(iy) && continue
      iseven(ix) && iseven(iy) && continue
      circle(O+dx*ix+dy*iy, 10, action=:fill)
    end
    setcolor(sethue("orchid1")...,0.5)
    for ix = -Nx:Nx, iy = -Ny:Ny
      isodd(ix) && isodd(iy) && continue
      iseven(ix) && iseven(iy) && continue
      circle(O+dx*(1+ix)+dy*iy, 8, action=:fill)
    end
    circle(O, jl_radius, action = :clip)
end

# stiches v2
setline(8)
setlinecap(:round)
for (c,color) in ((patch_pt_red,"darkred"),
                  (patch_pt_purple,"purple4"),
                  (patch_pt_green,"darkgreen"))
  setcolor(color)
  ps = ngon(c, jl_radius, 20, rand((-π/3,π/3)), vertices=true)
  pp1 = ps[1]
  for p in ps
    dir = (c-p)/norm(c-p)
    l = rand((0.9,1.1))*5*dir
    rng = (-1,1)
    α = rand((-π/30,π/30))
    l2m = rotatepoint(p-l,p,α)
    l2p = rotatepoint(p+l,p,α)
    line(p, l2m, action=:stroke)
    line(p, l2p, action=:stroke)
  end
end

# setcolor("blue")
# circle(center_gray, 10, action=:fill)
# circle(center_patch, 10, action=:fill)
# p1, p2, p3 = ngon(center_gray, trio_radius, 3, -π/2, vertices=true)
# circle(p1, 10, action=:fill)
# circle(p2, 10, action=:fill)
# circle(p3, 10, action=:fill)
# p1, p2, p3 = ngon(center_patch, s*80, 3, -π/2, vertices=true)
# circle(p1, 10, action=:fill)
# circle(p2, 10, action=:fill)
# circle(p3, 10, action=:fill)

# setcolor("black")
# setcolor("darkgray")
setcolor("grey55")
d = patch_pt_purple-gray_pt_purple
dd = d/norm(d)
pc = gray_pt_purple+d/2
p1 = gray_pt_purple+dd*110
p2 = patch_pt_purple-dd*110
# circle(p1, 10, action=:fill)
# circle(p2, 10, action=:fill)
pp1 = rotatepoint(p1, gray_pt_purple, π/5)
pp2 = rotatepoint(p2, patch_pt_purple, -π/5)
# circle(pp1, 10, action=:fill)
# circle(pp2, 10, action=:fill)
arrow(pp1, pp2, [-15,-15],
      arrowheadlength=60, arrowheadangle=π/6, linewidth=20)

# setcolor("orange")
d = patch_pt_green-gray_pt_green
dd = d/norm(d)
pc = gray_pt_green+d/2
# arrow(pc, norm(d)/2, π, π/2,
#       arrowheadlength=60, arrowheadangle=π/6, linewidth=20)
p1 = gray_pt_green+dd*110
p2 = patch_pt_green-dd*110
# circle(p1, 10, action=:fill)
# circle(p2, 10, action=:fill)
pp1 = rotatepoint(p1, gray_pt_green, -π/4)
pp2 = rotatepoint(p2, patch_pt_green, π/4)
# circle(pp1, 10, action=:fill)
# circle(pp2, 10, action=:fill)
arrow(pp1, pp2, [35,25],
      arrowheadlength=60, arrowheadangle=π/6, linewidth=20)

# p = center_gray+Point(100,-100)
# # circle(p, 10, action=:fill)
# fontface("Julia Mono Medium")
# fontsize(24)
# # setfont("Julia Mono Medium", 100)
# textbox([".text",
#          "push    rbx        ;llvm",
#          "movabs  rbx, 0x01  ;c&p"], p)

finish()
preview()

end
