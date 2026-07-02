local gdi32 = _G.KRNL_GDI32 or _G.LdrLoadDll("Windows/System32/gdi32.lua")
local etw = _G.LdrLoadDll("Windows/System32/etw.lua")
local hdc = gdi32.GetDC(0)

local Difficulty={
    beginner={rows=9,cols=9,mines=10},
    intermediate={rows=16,cols=16,mines=40},
    expert={rows=16,cols=30,mines=99}
}

local rows=Difficulty.beginner.rows
local cols=Difficulty.beginner.cols
local mines=Difficulty.beginner.mines

local CELL=2
local HEADER=4
local BORDER=1

local screenW=_G.HAL.w
local screenH=_G.HAL.h

local board={}
local revealed={}
local flagged={}

local timer=0
local minesLeft=mines

local gameOver=false
local gameWon=false
local firstClick=true

local C={
    BG=0x008080,

    WHITE=0xFFFFFF,
    LIGHT=0xE0E0E0,
    GRAY=0x808080,
    DARK=0x404040,
    BLACK=0x000000,

    RED=0xFF0000,
    BLUE=0x0000FF,
    GREEN=0x008000,
    NAVY=0x000080,
    MAROON=0x800000,
    CYAN=0x008080
}

local Brush={
    bg=gdi32.CreateSolidBrush(C.BG),
    white=gdi32.CreateSolidBrush(C.WHITE),
    gray=gdi32.CreateSolidBrush(C.GRAY),
    dark=gdi32.CreateSolidBrush(C.DARK),
    light=gdi32.CreateSolidBrush(C.LIGHT),
    black=gdi32.CreateSolidBrush(C.BLACK),
    red=gdi32.CreateSolidBrush(C.RED)
}

local Win={}

local function CalculateWindow()

    local maxCellX=math.floor((screenW-6)/cols)
    local maxCellY=math.floor((screenH-8)/rows)

    CELL=math.min(maxCellX,maxCellY)

    if CELL<2 then CELL=2 end
    if CELL>4 then CELL=4 end

    Win.BoardW=cols*CELL
    Win.BoardH=rows*CELL

    Win.W=Win.BoardW+2
    Win.H=Win.BoardH+HEADER-5

    Win.X=math.floor((screenW-Win.W)/2)
    Win.Y=math.floor((screenH-Win.H)/2)

    Win.BoardX=Win.X+1
    Win.BoardY=Win.Y+HEADER

end

local function Fill(x,y,w,h,brush)

    gdi32.SelectObject(hdc,brush)
    gdi32.PatBlt(hdc,x,y,w,h,gdi32.PATCOPY)

end

local function DrawText(x,y,color,text,bg)

    gdi32.SetTextColor(hdc,color)

    if bg then
        gdi32.SetBkColor(hdc,bg)
    end

    gdi32.TextOut(hdc,x,y,text)

end

local function Draw3D(x,y,w,h,raised)

    if raised then

        Fill(x,y,w,1,Brush.white)
        Fill(x,y,1,h,Brush.white)

        Fill(x+w-1,y,1,h,Brush.dark)
        Fill(x,y+h-1,w,1,Brush.dark)

    else

        Fill(x,y,w,1,Brush.dark)
        Fill(x,y,1,h,Brush.dark)

        Fill(x+w-1,y,1,h,Brush.white)
        Fill(x,y+h-1,w,1,Brush.white)

    end

end

local function DrawCounter(x,y,value)

    Draw3D(x,y,6,3,false)

    local txt=string.format("%03d",value)

    Fill(x+1,y+1,4,1,Brush.black)

    DrawText(x+1,y+1,C.RED,txt,C.BLACK)

end

local function DrawFace()

    local x=Win.X+math.floor(Win.W/2)-1
    local y=Win.Y+1

    Draw3D(x,y,3,3,true)

    local face=":)"

    if gameOver then
        face="XX"
    elseif gameWon then
        face="8)"
    end

    DrawText(x,y,C.BLACK,face,C.BG)

end

local function DrawHeader()

    Fill(Win.X,Win.Y,Win.W,HEADER,Brush.bg)

    Draw3D(
        Win.X,
        Win.Y,
        Win.W,
        HEADER,
        true
    )

    DrawCounter(
        Win.X+1,
        Win.Y+1,
        minesLeft
    )

    DrawFace()

    DrawCounter(
        Win.X+Win.W-10,
        Win.Y+1,
        math.floor(timer)
    )
    local CloseX=Win.X+Win.W-4
    local CloseY=Win.Y+1

    Draw3D(
        CloseX,
        CloseY,
        3,
        3,
        true
    )

    DrawText(
        CloseX+1,
        CloseY+1,
        C.BLACK,
        "X",
        C.BG
    )
end

local function DrawFrame()

    Fill(
        Win.X,
        Win.Y,
        Win.W,
        Win.H,
        Brush.bg
    )

    Draw3D(
        Win.X,
        Win.Y,
        Win.W,
        Win.H,
        true
    )

    DrawHeader()

end

local NumberColor={
    [1]=C.BLUE,
    [2]=C.GREEN,
    [3]=C.RED,
    [4]=C.NAVY,
    [5]=C.MAROON,
    [6]=C.CYAN,
    [7]=C.BLACK,
    [8]=C.GRAY
}

CalculateWindow()
DrawFrame()

local function DrawCell(r,c)

    local x=Win.BoardX+(c-1)*CELL
    local y=Win.BoardY+(r-1)*CELL

    if revealed[r][c] then

        Fill(x,y,CELL,CELL,Brush.light)

        if board[r][c]==-1 then

            DrawText(
                x,
                y,
                C.RED,
                "*",
                C.LIGHT
            )

        elseif board[r][c]>0 then

            DrawText(
                x,
                y,
                NumberColor[board[r][c]] or C.BLACK,
                tostring(board[r][c]),
                C.LIGHT
            )

        end

    else

        Fill(x,y,CELL,CELL,Brush.bg)

        Draw3D(
            x,
            y,
            CELL,
            CELL,
            true
        )

        if flagged[r][c] then

            DrawText(
                x,
                y,
                C.RED,
                "F",
                C.RED
            )

        end

    end

end

local function DrawBoard()

    Fill(
        Win.BoardX,
        Win.BoardY,
        Win.BoardW,
        Win.BoardH,
        Brush.bg
    )

    Draw3D(
        Win.BoardX-1,
        Win.BoardY-1,
        Win.BoardW+2,
        Win.BoardH+2,
        false
    )

    for r=1,rows do

        for c=1,cols do

            DrawCell(r,c)

        end

    end

end

local function Redraw()

    DrawFrame()
    DrawBoard()

end

local function InitBoard()

    board={}
    revealed={}
    flagged={}

    for r=1,rows do

        board[r]={}
        revealed[r]={}
        flagged[r]={}

        for c=1,cols do

            board[r][c]=0
            revealed[r][c]=false
            flagged[r][c]=false

        end

    end

    timer=0
    minesLeft=mines

    gameOver=false
    gameWon=false
    firstClick=true

    Redraw()

end

InitBoard()

local function PlaceMines(sr,sc)

    local placed=0

    while placed<mines do

        local r=math.random(rows)
        local c=math.random(cols)

        if board[r][c]~= -1 and not(
            math.abs(r-sr)<=1 and
            math.abs(c-sc)<=1
        ) then

            board[r][c]=-1
            placed=placed+1

        end

    end

    for r=1,rows do

        for c=1,cols do

            if board[r][c]~=-1 then

                local n=0

                for dy=-1,1 do
                    for dx=-1,1 do

                        local rr=r+dy
                        local cc=c+dx

                        if board[rr] and board[rr][cc]==-1 then
                            n=n+1
                        end

                    end
                end

                board[r][c]=n

            end

        end

    end

end

local function Flood(r,c)

    local q={{r,c}}

    while #q>0 do

        local node=table.remove(q,1)

        local y=node[1]
        local x=node[2]

        if not revealed[y][x] and not flagged[y][x] then

            revealed[y][x]=true

            if board[y][x]==0 then

                for dy=-1,1 do
                    for dx=-1,1 do

                        local yy=y+dy
                        local xx=x+dx

                        if board[yy]
                        and board[yy][xx]
                        and not revealed[yy][xx]
                        then

                            q[#q+1]={yy,xx}

                        end

                    end
                end

            end

        end

    end

end

local function CheckWin()

    local open=0

    for r=1,rows do
        for c=1,cols do

            if revealed[r][c] then
                open=open+1
            end

        end
    end

    if open==rows*cols-mines then

        gameWon=true
        gameOver=true

        for r=1,rows do
            for c=1,cols do

                if board[r][c]==-1 then
                    flagged[r][c]=true
                end

            end
        end

    end

end

local function Reveal(r,c)

    if gameOver then return end
    if flagged[r][c] then return end
    if revealed[r][c] then return end

    if firstClick then

        firstClick=false
        PlaceMines(r,c)

    end

    if board[r][c]==-1 then

        gameOver=true

        for y=1,rows do
            for x=1,cols do

                if board[y][x]==-1 then
                    revealed[y][x]=true
                end

            end
        end

        Redraw()

        return

    end

    if board[r][c]==0 then
        Flood(r,c)
    else
        revealed[r][c]=true
    end

    CheckWin()

    Redraw()

end

local function ToggleFlag(r,c)

    if gameOver then return end
    if revealed[r][c] then return end

    flagged[r][c]=not flagged[r][c]

    if flagged[r][c] then
        minesLeft=minesLeft-1
    else
        minesLeft=minesLeft+1
    end

    DrawHeader()
    DrawCell(r,c)

end

local function CellFromScreen(x,y)

    local c=math.floor((x-Win.BoardX)/CELL)+1
    local r=math.floor((y-Win.BoardY)/CELL)+1

    if r<1 or r>rows then return end
    if c<1 or c>cols then return end

    return r,c

end

local function Restart()

    InitBoard()

end

local function HandleClick(x,y,button)
    local closeX=Win.X+Win.W-4
    local closeY=Win.Y+1

    if x>=closeX and x<closeX+3 and
    y>=closeY and y<closeY+3 then
        return "close"
    end

    local fx=Win.X+math.floor(Win.W/2)-1
    local fy=Win.Y+1

    if x>=fx and x<fx+3 and
       y>=fy and y<fy+3 then

        Restart()
        return
    end

    local r,c=CellFromScreen(x,y)

    if not r then
        return
    end

    if button==1 then
        Reveal(r,c)
    elseif button==0 then
        ToggleFlag(r,c)
    end
end

local lastTick=computer.uptime()

Redraw()

while true do

    local now=computer.uptime()

    if not gameOver and not firstClick then

        if now-lastTick>=1 then

            timer=timer+1
            lastTick=now

            DrawHeader()

        end

    end

    local name,a,b,c,d,e=etw.ReadData(0.05)
    if name=="touch" then
        local r=HandleClick(
            b,
            c,
            d or 1
        )

        if r=="close" then
            break
        end

    elseif name=="key_down" then

        -- <

        if c==203 then
            break
        end

        -- F2 = restart

        if d==60 then
            Restart()
        end

    end

end

Fill(
    Win.X,
    Win.Y,
    Win.W,
    Win.H,
    Brush.bg
)

return true