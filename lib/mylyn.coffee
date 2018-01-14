{TaskList,FileList} = require("./TaskList")
{$} = require('atom-space-pen-views')
{saveState} = require("./common")

{MessagePanelView, PlainMessageView, LineMessageView} = require 'atom-message-panel'
_ = require "lodash"
InputDialog = require '@aki77/atom-input-dialog'
view = null
class Mylyn
  observer:null

  constructor:(@view,@mylyn)->
    if !@mylyn
        @mylyn =
              lastSelectedFile:undefined
              selectedFile:undefined
              currentTask:null
              tasks:[]
              filterOn:false
              enabled:false
    @observer =  atom.workspace.onDidChangeActivePaneItem((e)=>
        @onDidChangeActivePaneItem(e)
        )
    @reloadTreeView()

  toRelPath:(path)->
    relPaths = atom.project.relativizePath(path)
    proFolder =
      if relPaths[0]
        relPaths[0].split("/")
      else
        ""
    proFolder = proFolder[proFolder.length-1]
    proPath = proFolder+"/"+relPaths[1]
    proPath

  save:()->
        saveState(@mylyn)

  toggleEnabled:()->
    @mylyn.enabled = !@mylyn.enabled
    if @mylyn.enabled
      @mylyn.filterOn = true
    @reloadTreeView()

  deleteTask:(task)=>
      @mylyn.tasks = @mylyn.tasks.filter (t)->t!=task
      if @mylyn.currentTask==task then @mylyn.currentTask=null
      @focusActivePane()
      @save()

  filterOn: =>
    #return false
    @mylyn.filterOn&@mylyn.currentTask!=null&@mylyn.enabled

  focusActivePane:=>
      active =  atom.workspace.getActivePane()
      if active then active.activate()

  createTask:(name)=>
      task =
              name:name
              files:[]
      @mylyn.tasks.push(task)
      @save()
      task

  reloadTreeView:()=>
      console.log @view
      @view.treeViewOpenPromise
                .then (view)=>
                      selectedPath = view.selectedEntry()?.getPath()
                      view.updateRoots()
                      if selectedPath
                        view.selectEntryForPath selectedPath
                      @rebuild()

  selectFile:(callback)=>
    if @mylyn.currentTask
      new FileList @mylyn.currentTask.lastSelectedFile,@mylyn.currentTask.files,(file)=>
          callback(file)
          @focusActivePane()

  selectTask:(callback)=>
    currentTask= @mylyn.currentTask
    tasks = @mylyn.tasks#.sort (t)->t.name+(t!=(@mylyn.currentTask))
    new TaskList @mylyn.currentTask,@mylyn.tasks,(task)=>
        callback(task)
        @focusActivePane()

  enableAll: ->
      @mylyn.enabled = true
      @mylyn.filterOn = true

  switchTask:()=>
    @selectTask (task)=>
      @enableAll()
      @mylyn.currentTask = task
      @save()
      @reloadTreeView()

  switchFile:()=>
      @selectFile (file)=>
            uri = "//"+file.path
            getRealFilePath = (path)->
                      projectRoot = _.first path.split("/")
                      projectPaths = atom.project.getPaths()
                      root = _.find projectPaths,(p)->
                                    pp = _.last p.split("/")
                                    pp==projectRoot
                      if root
                        rootArray = root.split("/")
                        restOfProject = (_.tail path.split("/"))
                        allPathArray = _.tail(_.concat rootArray,restOfProject)
                        finalPath = _.reduce allPathArray, ((acc,p)->acc+"/"+p),""
                        finalPath
            realPath = getRealFilePath file.path
            @mylyn.currentTask.lastSelectedFile = @mylyn.currentTask.selectedFile
            @mylyn.currentTask.selectedFile = file
            @save()
            atom.workspace.open realPath,{searchAllPanes:true}


  getFilePaths:()=>
    @getFiles().map (f)->f.path

  isDirAllowed:(dir)=>
      if @filterOn()
        dir = @toRelPath(dir)
        @getFilePaths().find((file)->(""+file).startsWith(dir))!=undefined
      else
        true

  isFileAllowed:(file)=>
    if @filterOn()
      relFile = @toRelPath(file)
      relFile in @getFilePaths()
    else
      true


  withCurrentTask:(f)->
    if @mylyn.currentTask
      f(@mylyn.currentTask)

  getFiles: ()=>
    if @mylyn.currentTask
      @mylyn.currentTask.files
    else
      []

  hasFile:(file)=>
    file in @getFilePaths()

  getFile:(file)=>
    @getFiles().find (f)=>f.path is file


  addFile:(path)=>
        startPoints = 400
        @getFiles().forEach (f)->
            f.points = f.points-5
        if !@hasFile path
            file =
                path:path
                points:startPoints
            @getFiles().push(file)
            return false
          else
            file = @getFile(path)
            file.points=startPoints
            return true




  renameTask:(task,newName)=>
      @mylyn.currentTask.name = newName
      @save()

  showActiveFiles:()->

  renameCurrentTaskConfirm:()=>
    if @mylyn.currentTask==null then return
    dialog = new InputDialog
          prompt:"Rename task "+@mylyn.currentTask.name
          defaultText:@mylyn.currentTask.name
          callback: (name) =>
              @renameTask(@mylyn.currentTask,name)
              @save()
              @focusActivePane()
    dialog.attach()


  deleteTaskConfirm:()=>
    @selectTask (task)=>
        @deleteTask(task)
        @reloadTreeView()




  showDialog:(prompt,defaultText,callback)=>
    dialog = new InputDialog
          prompt:prompt
          defaultText:defaultText
          callback: callback
    dialog.attach()

  deleteAllTasks:->
    @showDialog "Delete all tasks (Yes/No)","No",(answer)=>
          if(answer=="Yes")
            @mylyn.tasks = []
            @mylyn.currentTask = null
          @reloadTreeView()
  newTask:() =>
    @showDialog "New task","",(name)=>
          @mylyn.currentTask = @createTask(name)
          @enableAll()
          @reloadTreeView()
          @focusActivePane()


  getState:()->@mylyn

  out:(o)=>
      console.log o
      @out


  hide: (e,isAllowed)=>
    span = $(e).find("span").first()
    path = $(span).attr("data-path")
    if !isAllowed(path)
        $(e).remove()
        #$(e).replaceWith($('<h5>' + e.innerHTML + '</h5>'));
        #$(e).addClass("mylyn-hidden")

        #$(e).addClass("status-ignored")
        #$(e).removeClass("entry")
    #else

    #    $(e).removeClass("mylyn-hidden")
    #    #$(e).addClass("entry")
    #    $(e).removeClass("status-ignored")


  hideDir:(e)=>
      @hide(e,@isDirAllowed)

  hideFile:(e)=>
      @hide(e,@isFileAllowed)

  hideDirs:=>
      dirs = @getDomDirs()
      dirs.each (i,e)=>@hideDir(e)
  hideFiles:=>
      files = @getDomFiles()
      files.each (i,e)=>@hideFile(e)

  listenForEvents:(entry)->
      if entry.onDidExpand
          entry.onDidExpand((d)=>@rebuild())

      if entry.entries
          #$.each entry.entries, (key, value)->console.log(key, value)
          $.each entry.entries, (key, value)=>@listenForEvents value
          #@out("entr")(entry.entries)
          #entry.entries.forEach @listenForEvents
  rebuild:()=>

    @hideDirs()
    @hideFiles()
    @view.treeView.roots.forEach (root)=>@listenForEvents root.directory
    rootDir = @view.treeView.roots[0].directory

  getDomFiles: =>$(".tree-view [is='tree-view-file']")


  getDomDirs: => $(".tree-view [is='tree-view-directory']")#.css("display","none")


  removeFile:(file)=>

  updateFiles:()=> @mylyn.currentTask.files =  @getFiles().filter (f)->f.points>0


  onDidChangeActivePaneItem:(e)=>
        workspaceView = atom.views.getView(atom.workspace)
        activeEditor = atom.workspace.getActiveTextEditor()
        activePane = atom.workspace.getActivePane();
        if activeEditor and @mylyn.enabled and @mylyn.currentTask
          path =  @toRelPath(activeEditor.getBuffer().getPath())
          @addFile(path)
          @updateFiles()
          @save()
          @reloadTreeView()


  toggleFilter:=>
    @mylyn.filterOn = !@mylyn.filterOn
    if @mylyn.filterOn
      @mylyn.enabled = true
    @reloadTreeView()


module.exports =
    Mylyn:Mylyn
