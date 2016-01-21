#!/usr/bin/env python

from ipykernel.kernelbase import Kernel
import casacore.tables as pt
import sys
import six
import re
import numpy

class TaQLKernel(Kernel):
    implementation = 'TaQL'
    implementation_version = '0.1'
    language = 'taql'
    language_version = '2.1'
    language_info = {'mimetype': 'text/plain', 'name': 'taql'}
    banner = "TaQL - Table Query Language from Casacore"

    def format_cell(self, val, colkeywords):
        out=""
  
        # String arrays are returned as dict, undo that for printing
        if isinstance(val, dict):
            tmpdict=numpy.array(val['array'])
            tmpdict.reshape(val['shape'])
            # Leave out quotes around strings
            numpy.set_printoptions(formatter={'all':lambda x: str(x)})
            out+=str(tmpdict)
            numpy.set_printoptions(formatter=None)
        else:
            out+=str(val)

        if 'QuantumUnits' in colkeywords:
            # Multiple different units for element in an array. TODO: do this properly
            # For now, just print the units and let the user figure out what it means
            if not (numpy.array(colkeywords['QuantumUnits'])==colkeywords['QuantumUnits'][0]).all():
                out+=str(colkeywords['QuantumUnits'])
            out+=" "+colkeywords['QuantumUnits'][0]

        return out

    def format_row(self, t, row):
        out=""
        previous_cell_was_multiline=False
        firstcell=True
        for colname in t.colnames():
            cellout=self.format_cell(row[colname], t.getcolkeywords(colname))

            if not(firstcell):
                if previous_cell_was_multiline:
                    out+="\n"
                else:
                    if "\n" in cellout:
                        previous_cell_was_multiline=True
                        out+="\n"
                    else:
                        out+="\t" 
            firstcell=False

            out+=cellout
        return out

    def format_table(self, t, printrows, printcount):
        out=""
        # Print number of rows, but not for simple calc expressions
        if printcount or (t.nrows()>=100):
            out+="Select result of "+str(t.nrows())+" row"
            if t.nrows()>1:
                out+="s\n"
            else:
                out+="\n"
        # Print column names (not if they are all auto-generated)
        if not all([colname[:4]=="Col_" for colname in t.colnames()]):
            if t.nrows()>0 and not "\n" in self.format_row(t,t[0]): # Try to get spacing right
                for colname in t.colnames():
                    firstval=self.format_cell(t[0][colname],t.getcolkeywords(colname))
                    out+=colname+" "*(len(firstval)-len(colname))+"\t"
            else:
                for colname in t.colnames():
                    out+=colname+"\t"
            out+="\n"
        if printrows:
            rowcount=0
            for row in t:
                rowout=self.format_row(t, row)
                rowcount+=1
                out+=rowout
                if "\n" in rowout: # Double space after multiline rows
                    out+="\n"
                out+="\n"
                if rowcount>=100:
                    out+=".\n.\n.\n("+str(t.nrows()-100)+" more rows)\n"
                    break
            
        return out

    def format_output(self, t, printrows, printcount):
        numpy.set_printoptions(precision=5)
        if isinstance(t, pt.table):
            return self.format_table(t, printrows, printcount)
        else:
            return str(t[0])

    def do_execute(self, code, silent, store_history=True, user_expressions=None,
                   allow_stdin=False):
        if not silent:
            code=str(code) # Code seems to be unicode, convert to string here
            if not ("select" in code.lower() or "update" in code.lower() or "insert" in code.lower() or "delete" in code.lower() or "count" in code.lower() or "calc" in code.lower() or "alter" in code.lower()):
                code="SELECT "+code           
   
            try:
                t=pt.taql(code)
                # Don't display output if code is 'SELECT FROM'
                printrows=True
                match = re.match('^.*?select(.*?)from',code, re.IGNORECASE)
                if match and match.group(1).isspace():
                    printrows=False

                # Don't display row count in simple calc-like expressions
                printcount=False
                if 'from' in code.lower():
                    printcount=True

                output=self.format_output(t,printrows,printcount)
            except RuntimeError as e:
                myerror=str(e).split('\n')
                output=""
                output+=myerror[0]+"\n"
                m = re.search('position (\d+) ', myerror[1])
                if (m):
                    pos=int(m.group(1))
                    output+=myerror[1]+":"+" "*(21+pos-len(myerror[1]))+"^\n"
                else:
                    output+="\n".join(myerror[1:])

            stream_content = {'name': 'stdout', 'text': output}
            self.send_response(self.iopub_socket, 'stream', stream_content)

        return {'status': 'ok',
                # The base class increments the execution count
                'execution_count': self.execution_count,
                'payload': [],
                'user_expressions': {},
               }

if __name__ == '__main__':
    from ipykernel.kernelapp import IPKernelApp
    IPKernelApp.launch_instance(kernel_class=TaQLKernel)

