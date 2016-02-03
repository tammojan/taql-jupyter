#!/usr/bin/env python

from ipykernel.kernelbase import Kernel
import casacore.tables as pt
import casacore.quanta as quanta
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

    def format_date(self, val, unit):
        if val==numpy.floor(val):
            # Do not show time part if 0
            return quanta.quantity(val,unit).formatted('YMD_ONLY')
        else:
            return quanta.quantity(val,unit).formatted('DMY')

    def format_quantum(self, val, unit):
        if unit in ['rad','s','d']:
            return str(val)+' '+unit
        else:
            return quanta.quantity(val, unit).formatted()

    def format_cell(self, val, colkeywords):
        out=""

        # String arrays are returned as dict, undo that for printing
        if isinstance(val, dict):
            tmpdict=numpy.array(val['array'])
            tmpdict.reshape(val['shape'])
            # Leave out quotes around strings
            numpy.set_printoptions(formatter={'all':lambda x: str(x)})
            out+=numpy.array2string(tmpdict, separator=', ')
            numpy.set_printoptions(formatter=None)
        else:
            valtype='other'
            singleUnit=('QuantumUnits' in colkeywords and (numpy.array(colkeywords['QuantumUnits'])==numpy.array(colkeywords['QuantumUnits'])[0]).all())
            if colkeywords.get('MEASINFO',{}).get('type')=='epoch' and singleUnit:
                # Format a date/time. Use quanta for scalars, use numpy for array logic around it (quanta does not support higher dimensional arrays)
                valtype='epoch'
                if isinstance(val, numpy.ndarray):
                    numpy.set_printoptions(formatter={'all':lambda x: self.format_date(x,colkeywords['QuantumUnits'][0])})
                    out+=numpy.array2string(val,separator=', ')
                    numpy.set_printoptions(formatter=None)
                else:
                    out+=self.format_date(val,colkeywords['QuantumUnits'][0])
            elif colkeywords.get('MEASINFO',{}).get('type')=='direction' and singleUnit and val.shape==(1,2):
                # Format one direction. TODO: extend to array of directions
                    valtype='direction'
                    out+="["
                    part=quanta.quantity(val[0,0],'rad').formatted("TIME",precision=9)
                    part=re.sub(r'(\d+):(\d+):(.*)',r'\1h\2m\3',part)
                    out+=part+", "
                    part=quanta.quantity(val[0,1],'rad').formatted("ANGLE",precision=9)
                    part=re.sub(r'(\d+)\.(\d+)\.(.*)',r'\1d\2m\3',part)
                    out+=part+"]"
            elif isinstance(val, numpy.ndarray) and singleUnit:
                # Format any array with units
                valtype='quanta'
                numpy.set_printoptions(formatter={'all':lambda x: self.format_quantum(x, colkeywords['QuantumUnits'][0])})
                out+=numpy.array2string(val,separator=', ')
                numpy.set_printoptions(formatter=None)
            elif isinstance(val, numpy.ndarray):
                # Undo quotes around strings
                numpy.set_printoptions(formatter={'all':lambda x: str(x)})
                out+=numpy.array2string(val,separator=', ')
                numpy.set_printoptions(formatter=None)
            else:
                out+=str(val)

        if 'QuantumUnits' in colkeywords and valtype=='other':
            # Print units if they haven't been taken care of
            if not (numpy.array(colkeywords['QuantumUnits'])==numpy.array(colkeywords['QuantumUnits'])[0]).all():
                # Multiple different units for element in an array. TODO: do this properly
                # For now, just print the units and let the user figure out what it means
                out+=" "+str(colkeywords['QuantumUnits'])
            else:
                out+=" "+colkeywords['QuantumUnits'][0]

        # Numpy sometimes adds double newlines, don't do that
        out=out.replace('\n\n','\n')
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

    def format_table(self, t, printrows, printcount, operation):
        out=""
        # Print number of rows, but not for simple calc expressions
        if printcount or (t.nrows()>=100):
            out+=operation.capitalize()+" result of "+str(t.nrows())+" row"
            if t.nrows()>1:
                out+="s\n"
            else:
                out+="\n"
        # Print column names (not if they are all auto-generated)
        if operation=="select" and not(all([colname[:4]=="Col_" for colname in t.colnames()])):
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

        if out[-2:]=="\n\n":
            out=out[:-1]
        return out

    def format_output(self, t, printrows, printcount, operation):
        numpy.set_printoptions(precision=5)
        if isinstance(t, pt.table):
            return self.format_table(t, printrows, printcount, operation)
        else:
            return str(t[0])

    def do_execute(self, code, silent, store_history=True, user_expressions=None,
                   allow_stdin=False):
        if not silent:
            output=""
            try:
                code=re.sub(ur"([0-9\s\.\)\"])\xb5([A-Za-z])",ur"\1u\2",code) # Tolerate µ as prefix for a unit, substitute it with u
                code=re.sub(ur"\u2245",ur"~=",code) # Tolerate ≅ for approximately equal
                code=str(code) # Code seems to be unicode, convert to string here
                if not ("select" in code.lower() or "update" in code.lower() or "insert" in code.lower() or "delete" in code.lower() or "count" in code.lower() or "calc" in code.lower() or "alter" in code.lower()):
                    code="SELECT "+code

                t=pt.taql(code)

                # match the first operation keyword, so that "select * from (update ..." will yield rows
                m=re.match(".*?((?:select)|(?:update)|(?:insert)|(?:delete)|(?:count)|(?:calc)|(?:create table)|(?:insert)|(?:alter table))",code.lower())
                if m:
                    operation=m.group(1)
                else:
                    operation="calc"

                # Don't display output if code is 'SELECT FROM'
                printrows=False
                if operation=="select":
                    # first select has something between "select" and "from"
                    match = re.match('^.*?select(.*?)from',code, re.IGNORECASE)
                    if not(match and match.group(1).isspace()):
                        printrows=True

                printcount=True
                # Don't display row count in simple calc-like expressions
                if operation=="select" and not('from' in code.lower()):
                    printcount=False

                output=self.format_output(t,printrows,printcount,operation)
            except UnicodeEncodeError as e:
                output+="Error: unicode is not supported"
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

